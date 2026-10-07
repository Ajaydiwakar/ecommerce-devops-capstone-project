package com.ecommerce;

import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.ActiveProfiles;

// This ensures the Spring context can load successfully
@SpringBootTest
@ActiveProfiles("test") // Prevents it from trying to connect to a real RDS/Redis during the CI pipeline build
class EcommerceApplicationTests {

    @Test
    void contextLoads() {
        // If the application fails to start (e.g., missing dependencies), this test will fail
        // and Surefire will stop the Jenkins pipeline.
    }
}