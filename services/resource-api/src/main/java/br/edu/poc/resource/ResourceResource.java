package br.edu.poc.resource;

import io.quarkus.security.Authenticated;
import io.quarkus.security.identity.SecurityIdentity;
import jakarta.annotation.security.PermitAll;
import jakarta.annotation.security.RolesAllowed;
import jakarta.inject.Inject;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;
import org.jboss.logging.Logger;

import java.util.Map;
import java.util.stream.Collectors;

@Path("/api")
@Produces(MediaType.APPLICATION_JSON)
public class ResourceResource {
    private static final Logger LOG = Logger.getLogger(ResourceResource.class);

    @Inject
    SecurityIdentity identity;

    @GET
    @Path("/public")
    @PermitAll
    public Map<String, String> publicResource() {
        LOG.info("service=resource-api path=/api/public status=200");
        return Map.of("message", "public");
    }

    @GET
    @Path("/protected")
    @RolesAllowed("user")
    public Map<String, String> protectedResource() {
        LOG.infof("service=resource-api path=/api/protected user=%s status=200", username());
        return Map.of("message", "protected");
    }

    @GET
    @Path("/admin")
    @RolesAllowed("admin")
    public Map<String, String> adminResource() {
        LOG.infof("service=resource-api path=/api/admin user=%s status=200", username());
        return Map.of("message", "admin");
    }

    @GET
    @Path("/me")
    @Authenticated
    public MeResponse me() {
        return new MeResponse(username(), identity.getRoles().stream().sorted().collect(Collectors.toList()));
    }

    @POST
    @Path("/preferences")
    @Consumes(MediaType.APPLICATION_JSON)
    @RolesAllowed("user")
    public Response preferences(Map<String, String> preferences) {
        LOG.infof("service=resource-api path=/api/preferences user=%s status=200", username());
        return Response.ok(Map.of("saved", true, "theme", preferences.getOrDefault("theme", "default"))).build();
    }

    private String username() {
        return identity.getPrincipal().getName();
    }

    public record MeResponse(String username, java.util.List<String> roles) {
    }
}

