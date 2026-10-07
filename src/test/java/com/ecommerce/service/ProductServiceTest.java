package com.ecommerce.service;

import com.ecommerce.model.Product;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.util.List;
import java.util.Optional;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class ProductServiceTest {

    @Mock
    private ProductRepository productRepository;

    @InjectMocks
    private ProductService productService;

    private Product mockProduct;

    @BeforeEach
    void setUp() {
        mockProduct = new Product();
        mockProduct.setId(42L);
        mockProduct.setName("iPhone 15");
        mockProduct.setDescription("A flagship smartphone with an advanced camera and vibrant OLED display.");
        mockProduct.setCategory("Electronics");
        mockProduct.setSizes("128GB, 256GB, 512GB");
        mockProduct.setPrice(999.00);
        mockProduct.setImageKey("products/iphone15.jpg");
    }

    @Test
    void getProduct_WhenProductExists_ReturnsProduct() {
        // Arrange
        when(productRepository.findById(42L)).thenReturn(Optional.of(mockProduct));

        // Act
        Product result = productService.getProduct(42L);

        // Assert
        assertNotNull(result, "Product should not be null");
        assertEquals("iPhone 15", result.getName());
        assertEquals("products/iphone15.jpg", result.getImageKey());
        
        // Verify repository was called (simulating the Cache MISS scenario)
        verify(productRepository, times(1)).findById(42L);
    }

    @Test
    void getProduct_WhenProductDoesNotExist_ReturnsNull() {
        // Arrange
        when(productRepository.findById(99L)).thenReturn(Optional.empty());

        // Act
        Product result = productService.getProduct(99L);

        // Assert
        assertNull(result, "Product should be null if not found in database");
    }

    @Test
    void getAllProducts_ReturnsCatalogWithDescriptionsAndSizes() {
        Product secondProduct = new Product();
        secondProduct.setId(43L);
        secondProduct.setName("Nike Air Max");
        secondProduct.setDescription("Lightweight running shoe with responsive cushioning.");
        secondProduct.setCategory("Footwear");
        secondProduct.setSizes("6, 7, 8, 9, 10");
        secondProduct.setPrice(149.00);
        secondProduct.setImageKey("products/nike-air-max.jpg");

        when(productRepository.findAll()).thenReturn(List.of(mockProduct, secondProduct));

        List<Product> result = productService.getAllProducts();

        assertNotNull(result);
        assertEquals(2, result.size());
        assertEquals("Electronics", result.get(0).getCategory());
        assertEquals("6, 7, 8, 9, 10", result.get(1).getSizes());
        verify(productRepository, times(1)).findAll();
    }

    @Test
    void saveProduct_ReturnsSavedProduct() {
        // Arrange
        when(productRepository.save(mockProduct)).thenReturn(mockProduct);

        // Act
        Product result = productService.saveProduct(mockProduct);

        // Assert
        assertNotNull(result);
        assertEquals(42L, result.getId());
        verify(productRepository, times(1)).save(mockProduct);
    }
}