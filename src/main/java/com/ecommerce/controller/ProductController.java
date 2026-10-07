package com.ecommerce.controller;

import com.ecommerce.model.Product;
import com.ecommerce.service.ProductService;
import com.ecommerce.service.S3Service;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.HashMap;
import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/products")
@CrossOrigin(origins = {"http://localhost:3000", "http://127.0.0.1:3000"}, allowCredentials = "true")
public class ProductController {

    private final ProductService productService;
    private final S3Service s3Service;

    public ProductController(ProductService productService, S3Service s3Service) {
        this.productService = productService;
        this.s3Service = s3Service;
    }

    @GetMapping
    public ResponseEntity<List<Map<String, Object>>> all() {
        List<Product> products = productService.getAllProducts();

        List<Map<String, Object>> response = products.stream()
                .map(product -> {
                    Map<String, Object> body = new HashMap<>();
                    body.put("product", product);
                    body.put("imageUrl", s3Service.getImageUrl(product.getImageKey()));
                    return body;
                })
                .toList();

        return ResponseEntity.ok(response);
    }

    @GetMapping("/{id}")
    public ResponseEntity<Map<String, Object>> one(@PathVariable Long id) {
        Product product = productService.getProduct(id);

        if (product == null) {
            return ResponseEntity.notFound().build();
        }

        Map<String, Object> body = new HashMap<>();
        body.put("product", product);
        body.put("imageUrl", s3Service.getImageUrl(product.getImageKey()));

        return ResponseEntity.ok(body);
    }
}