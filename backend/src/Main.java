import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpHandler;
import com.sun.net.httpserver.HttpServer;

import java.io.IOException;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.net.URI;
import java.net.URLDecoder;
import java.nio.charset.StandardCharsets;

public class Main {
    public static void main(String[] args) throws Exception {
        int port = 8080;
        HttpServer server = HttpServer.create(new InetSocketAddress(port), 0);

        // GET /health -> "OK"
        server.createContext("/health", exchange -> {
            
            exchange.getResponseHeaders().add("Access-Control-Allow-Origin", "*");

            byte[] resp = "OK".getBytes(StandardCharsets.UTF_8);
            exchange.sendResponseHeaders(200, resp.length);
            try (OutputStream os = exchange.getResponseBody()) {
                os.write(resp);
            }
        });

        // GET /message?name=abc -> "Hello abc"
        server.createContext("/message", new MessageHandler());

        server.setExecutor(null);
        server.start();
        System.out.println("Server started on port " + port);
    }

    static class MessageHandler implements HttpHandler {
        @Override
        public void handle(HttpExchange exchange) throws IOException {
            // allow calls from any origin
            exchange.getResponseHeaders().add("Access-Control-Allow-Origin", "*");

            URI uri = exchange.getRequestURI();
            String query = uri.getQuery();
            String name = "world";

            if (query != null) {
                for (String part : query.split("&")) {
                    String[] kv = part.split("=", 2);
                    if (kv.length == 2 && kv[0].equals("name")) {
                        name = URLDecoder.decode(kv[1], StandardCharsets.UTF_8);
                    }
                }
            }

            String response = "Hello " + name;
            byte[] respBytes = response.getBytes(StandardCharsets.UTF_8);
            exchange.sendResponseHeaders(200, respBytes.length);
            try (OutputStream os = exchange.getResponseBody()) {
                os.write(respBytes);
            }
        }
    }
}
