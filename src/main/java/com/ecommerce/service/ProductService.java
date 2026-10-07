package com.ecommerce.service;

import com.ecommerce.model.Product;
import org.springframework.cache.annotation.CacheEvict;
import org.springframework.cache.annotation.Cacheable;
import org.springframework.stereotype.Service;

import java.util.List;

@Service
public class ProductService {

    private final ProductRepository repository;

    public ProductService(ProductRepository repository) {
        this.repository = repository;
    }

    // Cache-aside pattern: checks Redis first, then falls back to MySQL.
    @Cacheable(value = "products", key = "#id")
    public Product getProduct(Long id) {
        return repository.findById(id).orElse(null);
    }

    @Cacheable(value = "products", key = "'all'")
    public List<Product> getAllProducts() {
        return repository.findAll();
    }

    // Keeps the cache honest by removing stale data on update.
    @CacheEvict(value = "products", allEntries = true)
    public Product saveProduct(Product product) {
        return repository.save(product);
    }
}