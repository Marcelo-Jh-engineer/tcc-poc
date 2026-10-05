package br.edu.poc.gateway;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.CookieParam;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.QueryParam;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;
import org.eclipse.microprofile.config.inject.ConfigProperty;
import org.jboss.logging.Logger;

import java.net.URI;
import java.net.URLEncoder;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.util.Base64;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;
import java.util.stream.Collectors;

@Path("/")
@Produces(MediaType.APPLICATION_JSON)
public class GatewayAuthResource {
    private static final Logger LOG = Logger.getLogger(GatewayAuthResource.class);
    private static final String COOKIE = "POC_GATEWAY_SESSION";
    @ConfigProperty(name = "keycloak.internal.url") String keycloakInternalUrl;
    @ConfigProperty(name = "keycloak.public.url") String keycloakPublicUrl;
    @ConfigProperty(name = "keycloak.realm") String realm;
    @ConfigProperty(name = "oidc.client.id") String clientId;
    @ConfigProperty(name = "oidc.client.secret") String clientSecret;
    @ConfigProperty(name = "oidc.redirect.uri") String redirectUri;
    @ConfigProperty(name = "resource.api.url") String resourceApiUrl;
    private final HttpClient http = HttpClient.newHttpClient();
    private final Map<String, Session> sessions = new ConcurrentHashMap<>();
    private final Map<String, Long> states = new ConcurrentHashMap<>();
    @jakarta.inject.Inject ObjectMapper mapper;

    @GET @Path("/auth/login")
    public Response login() {
        String state = UUID.randomUUID().toString(); states.put(state, System.currentTimeMillis() + 300_000);
        String endpoint = keycloakPublicUrl + "/realms/" + realm + "/protocol/openid-connect/auth";
        String url = endpoint + "?client_id=" + enc(clientId) + "&response_type=code&scope=openid%20profile%20email&redirect_uri=" + enc(redirectUri) + "&state=" + enc(state);
        return Response.seeOther(URI.create(url)).build();
    }

    @GET @Path("/auth/callback")
    public Response callback(@QueryParam("code") String code, @QueryParam("state") String state, @QueryParam("error") String error) {
        if (error != null || code == null || states.remove(state) == null) return Response.status(400).entity(Map.of("error", "invalid_oidc_callback")).build();
        try {
            JsonNode token = tokenRequest("grant_type=authorization_code&code=" + enc(code) + "&redirect_uri=" + enc(redirectUri));
            String id = UUID.randomUUID().toString(); sessions.put(id, sessionFrom(token));
            return Response.seeOther(URI.create("http://localhost:3001/?login=success")).header("Set-Cookie", cookie(id, false)).build();
        } catch (Exception e) { LOG.error("OIDC callback failed", e); return Response.serverError().entity(Map.of("error", "token_exchange_failed")).build(); }
    }

    @GET @Path("/auth/session")
    public Response session(@CookieParam(COOKIE) String id) {
        if (id == null || id.isBlank()) return Response.ok(Map.of("authenticated", false)).build();
        Session session = sessions.get(id); if (session == null) return Response.ok(Map.of("authenticated", false)).build();
        refreshIfNeeded(session); return Response.ok(Map.of("authenticated", true, "username", session.username, "roles", session.roles)).build();
    }

    @GET @Path("/auth/logout")
    public Response logout(@CookieParam(COOKIE) String id) {
        Session session = sessions.remove(id); String redirect = "http://localhost:3001/?logout=success";
        String url = keycloakPublicUrl + "/realms/" + realm + "/protocol/openid-connect/logout?client_id=" + enc(clientId) + "&post_logout_redirect_uri=" + enc(redirect);
        if (session != null && session.idToken != null) url += "&id_token_hint=" + enc(session.idToken);
        return Response.seeOther(URI.create(url)).header("Set-Cookie", cookie("", true)).build();
    }

    @GET @Path("/api/{path: .*}")
    public Response getApi(@PathParam("path") String path, @CookieParam(COOKIE) String id) { return proxy("GET", path, null, id); }

    @POST @Path("/api/{path: .*}") @Consumes(MediaType.APPLICATION_JSON)
    public Response postApi(@PathParam("path") String path, String body, @CookieParam(COOKIE) String id) { return proxy("POST", path, body, id); }

    private Response proxy(String method, String path, String body, String id) {
        Session session = sessions.get(id); if (session == null) return Response.status(401).entity(Map.of("error", "not_authenticated")).build();
        refreshIfNeeded(session);
        try {
            HttpRequest.Builder builder = HttpRequest.newBuilder(URI.create(resourceApiUrl + "/api/" + path)).header("Authorization", "Bearer " + session.accessToken);
            if ("POST".equals(method)) builder.header("Content-Type", MediaType.APPLICATION_JSON).POST(HttpRequest.BodyPublishers.ofString(body == null ? "" : body)); else builder.GET();
            HttpResponse<String> response = http.send(builder.build(), HttpResponse.BodyHandlers.ofString());
            return Response.status(response.statusCode()).type(MediaType.APPLICATION_JSON).entity(response.body()).build();
        } catch (Exception e) { LOG.error("resource-api proxy failed", e); return Response.serverError().entity(Map.of("error", "resource_api_unavailable")).build(); }
    }

    private JsonNode tokenRequest(String form) throws Exception {
        HttpRequest request = HttpRequest.newBuilder(URI.create(tokenEndpoint())).header("Content-Type", "application/x-www-form-urlencoded")
                .header("Authorization", "Basic " + Base64.getEncoder().encodeToString((clientId + ":" + clientSecret).getBytes(StandardCharsets.UTF_8)))
                .POST(HttpRequest.BodyPublishers.ofString(form)).build();
        HttpResponse<String> response = http.send(request, HttpResponse.BodyHandlers.ofString()); if (response.statusCode() >= 300) throw new IllegalStateException("token endpoint status " + response.statusCode());
        return mapper.readTree(response.body());
    }

    private void refreshIfNeeded(Session session) {
        if (session.expiresAt > Instant.now().getEpochSecond() + 30 || session.refreshToken == null) return;
        try { JsonNode token = tokenRequest("grant_type=refresh_token&refresh_token=" + enc(session.refreshToken)); Session next = sessionFrom(token); session.accessToken = next.accessToken; session.refreshToken = next.refreshToken == null ? session.refreshToken : next.refreshToken; session.expiresAt = next.expiresAt; }
        catch (Exception e) { LOG.warn("refresh failed; existing session remains until expiry"); }
    }

    private Session sessionFrom(JsonNode token) throws Exception {
        String access = token.path("access_token").asText(); JsonNode claims = mapper.readTree(new String(Base64.getUrlDecoder().decode(access.split("\\.")[1]), StandardCharsets.UTF_8));
        Set<String> roles = mapper.convertValue(claims.path("realm_access").path("roles"), Set.class);
        return new Session(access, token.path("refresh_token").asText(null), token.path("id_token").asText(null), claims.path("preferred_username").asText(claims.path("sub").asText("unknown")), roles, Instant.now().getEpochSecond() + token.path("expires_in").asLong(300));
    }

    private String tokenEndpoint() { return keycloakInternalUrl + "/realms/" + realm + "/protocol/openid-connect/token"; }
    private static String enc(String value) { return URLEncoder.encode(value, StandardCharsets.UTF_8); }
    private static String cookie(String value, boolean expired) { return COOKIE + "=" + value + "; Path=/; HttpOnly; SameSite=Lax" + (expired ? "; Max-Age=0" : ""); }
    private static final class Session {
        volatile String accessToken; volatile String refreshToken; final String idToken; final String username; final Set<String> roles; volatile long expiresAt;
        Session(String accessToken, String refreshToken, String idToken, String username, Set<String> roles, long expiresAt) { this.accessToken = accessToken; this.refreshToken = refreshToken; this.idToken = idToken; this.username = username; this.roles = roles.stream().sorted().collect(Collectors.toSet()); this.expiresAt = expiresAt; }
    }
}
