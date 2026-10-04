package br.edu.poc.internalapi;

import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;
import java.util.Map;

@Path("/internal")
@Produces(MediaType.APPLICATION_JSON)
public class InternalResource {
    @GET
    @Path("/data")
    public Map<String, String> data() {
        return Map.of("message", "internal", "service", "internal-api");
    }
}

