package com.ecommerce;

import com.ecommerce.model.Product;
import com.ecommerce.service.ProductRepository;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.boot.CommandLineRunner;
import org.springframework.cache.Cache;
import org.springframework.cache.CacheManager;
import org.springframework.stereotype.Component;

import java.util.ArrayList;
import java.util.List;

@Component
public class DataSeeder implements CommandLineRunner {

    private final ProductRepository productRepository;
    private final ObjectProvider<CacheManager> cacheManagerProvider;

    public DataSeeder(ProductRepository productRepository, ObjectProvider<CacheManager> cacheManagerProvider) {
        this.productRepository = productRepository;
        this.cacheManagerProvider = cacheManagerProvider;
    }

    @Override
    public void run(String... args) {
        CacheManager cacheManager = cacheManagerProvider.getIfAvailable();
        if (cacheManager != null) {
            Cache productsCache = cacheManager.getCache("products");
            if (productsCache != null) {
                productsCache.clear();
            }
        }

        long count = productRepository.count();

        if (count == 0) {
            List<Product> catalog = buildCatalog();
            productRepository.saveAll(catalog);
            System.out.println("Seeded 100 product catalog entries for S3-backed ecommerce data");
        }
    }

    private List<Product> buildCatalog() {
        List<String> names = List.of(
                "Leather Handbag", "Classic Watch", "Wireless Earbuds", "Running Shoes", "Smart Lamp",
                "Cotton Hoodie", "Denim Jacket", "Coffee Grinder", "Fitness Tracker", "Travel Backpack",
                "Bluetooth Speaker", "Sunglasses", "Desk Chair", "Laptop Sleeve", "Water Bottle",
                "Canvas Tote", "Office Chair", "Digital Camera", "Gaming Mouse", "Yoga Mat",
                "Phone Case", "Headphones", "Desk Lamp", "Backpack", "Sneakers", "T-Shirt", "Pillow",
                "Thermos", "Tablet Stand", "Laptop Cooler", "Luggage", "Hiking Boots", "Skincare Kit",
                "Coffee Mug", "Keyboard", "Monitor Stand", "Umbrella", "Power Bank", "Socks", "Jacket",
                "Perfume", "Belt", "Boots", "Sandal", "Sandals", "Candle", "Blanket", "Purse", "Wallet",
                "Monitor", "Keyboard", "Desk Organizer", "Wall Clock", "Flashlight", "Bowl", "Plate Set",
                "Rug", "Curtain", "Scarf", "Mask", "Speech", "Basket", "Bag", "Notebook", "Planner", "Pen Set",
                "Board Game", "Puzzle", "Cookware", "Cutlery", "Sports Bottle", "Camera Lens", "Drone", "Projector",
                "Speaker", "Vacuum", "Rice Cooker", "Air Fryer", "Mixer", "Blender", "Washing Machine", "Dryer",
                "Microwave", "Fridge", "Toaster", "Cooktop", "Lawn Mower", "Garden Set", "Tent", "Sleeping Bag",
                "Camp Chair", "Phone Stand", "Gaming Controller", "Console", "Webcam", "Microphone", "Tablet", "Smartwatch",
                "Hoodie", "Scuba Mask", "Wrist Watch", "Messenger Bag", "Rope", "Yoga Block", "Exercise Bike",
                "Dumbbell", "Fitness Band", "Home Speaker", "Mini Projector", "Air Purifier", "Robot Vacuum", "Heater"
        );

        List<Product> products = new ArrayList<>();
        for (int i = 1; i <= 100; i++) {
            Product product = new Product();
            product.setId((long) i);
            product.setName(names.get((i - 1) % names.size()) + " " + i);
            product.setDescription("Premium quality product designed for daily use, comfort, and long-term durability.");
            product.setCategory(i % 3 == 0 ? "Accessories" : i % 2 == 0 ? "Apparel" : "Electronics");
            product.setSizes("S, M, L, XL");
            product.setPrice(49.99 + (i * 12.75));
            product.setImageKey("products/product-" + i + ".jpg");
            products.add(product);
        }

        return products;
    }
}
