package br.edu.poc.resource;

import io.quarkus.security.Authenticated;
import io.quarkus.security.identity.SecurityIdentity;
import jakarta.annotation.security.PermitAll;
import jakarta.annotation.security.RolesAllowed;
import jakarta.inject.Inject;
import jakarta.transaction.Transactional;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.DELETE;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;
import org.jboss.logging.Logger;

import java.math.BigDecimal;
import java.time.OffsetDateTime;
import java.util.List;
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
    @Path("/products")
    @RolesAllowed("user")
    @Transactional
    public List<ProductResponse> products() {
        LOG.infof("service=resource-api path=/api/products user=%s status=200", username());
        seedCatalogIfNecessary();
        return ProductEntity.<ProductEntity>find("ownerSubject = ?1 order by id", ownerSubject())
            .list()
            .stream()
            .map(this::toResponse)
            .toList();
    }

    @POST
    @Path("/products")
    @Consumes(MediaType.APPLICATION_JSON)
    @RolesAllowed("user")
    @Transactional
    public Response createProduct(ProductRequest request) {
        if (request == null || isBlank(request.name()) || isBlank(request.icon()) || isBlank(request.category())
            || request.price() == null || request.price().signum() < 0) {
            return Response.status(Response.Status.BAD_REQUEST)
                .entity(Map.of("message", "name, price, icon e category sao obrigatorios"))
                .build();
        }

        ProductEntity product = new ProductEntity();
        product.ownerSubject = ownerSubject();
        product.ownerUsername = ownerUsername();
        product.name = request.name().trim();
        product.price = request.price();
        product.icon = request.icon().trim();
        product.category = request.category().trim();
        product.createdAt = OffsetDateTime.now();
        product.persist();
        return Response.status(Response.Status.CREATED).entity(toResponse(product)).build();
    }

    @DELETE
    @Path("/products/{id}")
    @RolesAllowed("user")
    @Transactional
    public Response deleteProduct(@PathParam("id") Long id) {
        ProductEntity product = ProductEntity.findById(id);
        if (product == null || !product.ownerSubject.equals(ownerSubject())) {
            return Response.status(Response.Status.NOT_FOUND).build();
        }

        product.delete();
        return Response.noContent().build();
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

    private void seedCatalogIfNecessary() {
        if (ProductEntity.count("ownerSubject", ownerSubject()) > 0) {
            return;
        }

        List.of(
            new ProductSeed("Caf\u00E9 Especial", "29.90", "\u2615", "Bebidas"),
            new ProductSeed("Fone Bluetooth", "199.90", "\uD83C\uDFA7", "Eletr\u00F4nicos"),
            new ProductSeed("Mochila Urbana", "149.90", "\uD83C\uDF92", "Acess\u00F3rios"),
            new ProductSeed("Livro de Seguran\u00E7a", "89.90", "\uD83D\uDCD8", "Livros")
        ).forEach(seed -> {
            ProductEntity product = new ProductEntity();
            product.ownerSubject = ownerSubject();
            product.ownerUsername = ownerUsername();
            product.name = seed.name();
            product.price = new BigDecimal(seed.price());
            product.icon = seed.icon();
            product.category = seed.category();
            product.createdAt = OffsetDateTime.now();
            product.persist();
        });
    }

    private ProductResponse toResponse(ProductEntity product) {
        return new ProductResponse(product.id, product.name, product.price, product.icon, product.category, product.ownerUsername);
    }

    private String ownerSubject() {
        Object subject = identity.getAttribute("sub");
        return subject == null ? identity.getPrincipal().getName() : subject.toString();
    }

    private String ownerUsername() {
        Object preferredUsername = identity.getAttribute("preferred_username");
        return preferredUsername == null ? identity.getPrincipal().getName() : preferredUsername.toString();
    }

    private String username() {
        return identity.getPrincipal().getName();
    }

    private boolean isBlank(String value) {
        return value == null || value.isBlank();
    }

    public record MeResponse(String username, List<String> roles) {
    }

    public record ProductResponse(Long id, String name, BigDecimal price, String icon, String category, String ownerUsername) {
    }

    public record ProductRequest(String name, BigDecimal price, String icon, String category) {
    }

    private record ProductSeed(String name, String price, String icon, String category) {
    }
}
