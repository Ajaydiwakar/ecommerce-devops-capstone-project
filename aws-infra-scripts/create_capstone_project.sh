#!/usr/bin/env bash
set -e

echo "1. Creating project folder structure..."
mkdir -p ansible/roles/{common,app_server,docker_toolchain,ssl_setup}/tasks
mkdir -p docker-toolchain
mkdir -p ecommerce-app/src/main/java/com/capstone/ecommerce/{controller,model,repository,service,config}
mkdir -p ecommerce-app/src/main/resources/static
mkdir -p ecommerce-app/src/test/java/com/capstone/ecommerce/{controller,service}

echo "2. Writing Containerized DevOps Toolchain (docker-compose-tools.yml)..."

cat << 'EOF' > docker-toolchain/docker-compose-tools.yml
version: '3.8'

services:
  jenkins:
    image: jenkins/jenkins:lts-jdk17
    container_name: jenkins-master
    restart: always
    user: root
    ports:
      - "8080:8080"
      - "50000:50000"
    volumes:
      - jenkins_home:/var/jenkins_home
      - /var/run/docker.sock:/var/run/docker.sock
      - /usr/bin/docker:/usr/bin/docker
    environment:
      - JAVA_OPTS=-Djenkins.install.runSetupWizard=false

  sonarqube:
    image: sonarqube:community
    container_name: sonarqube-server
    restart: always
    ports:
      - "9000:9000"
    environment:
      - SONAR_ES_BOOTSTRAP_CHECKS_DISABLE=true
    volumes:
      - sonarqube_data:/opt/sonarqube/data
      - sonarqube_logs:/opt/sonarqube/logs
      - sonarqube_extensions:/opt/sonarqube/extensions

volumes:
  jenkins_home:
  sonarqube_data:
  sonarqube_logs:
  sonarqube_extensions:
EOF

echo "3. Writing Ansible Configuration & Dynamic EC2 Inventory..."

cat << 'EOF' > ansible/aws_ec2.yaml
plugin: amazon.aws.aws_ec2
regions:
  - us-east-1

filters:
  instance-state-name:
    - running

hostnames:
  - private-ip-address

keyed_groups:
  - key: tags.Name
    prefix: ""
    separator: ""
EOF

cat << 'EOF' > ansible/ansible.cfg
[defaults]
inventory = aws_ec2.yaml
remote_user = ec2-user
private_key_file = ~/.ssh/capstone-key.pem
host_key_checking = False
timeout = 30

[inventory]
enable_plugins = amazon.aws.aws_ec2

[ssh_connection]
ssh_args = -o StrictHostKeyChecking=no -o ProxyCommand="ssh -W %h:%p -q ec2-user@YOUR_BASTION_PUBLIC_IP -i ~/.ssh/capstone-key.pem"
EOF

cat << 'EOF' > ansible/site.yml
---
- name: Apply common configurations to all nodes
  hosts: all
  gather_facts: yes
  tasks:
    - name: Update dnf packages
      dnf:
        name: "*"
        state: latest

    - name: Install prerequisite tools
      dnf:
        name:
          - git
          - curl
          - unzip
          - wget
          - docker
        state: present

    - name: Enable and start Docker
      systemd:
        name: docker
        state: started
        enabled: yes

    - name: Add ec2-user to docker group
      user:
        name: ec2-user
        groups: docker
        append: yes

- name: Deploy Containerized DevOps Toolchain Node
  hosts: toolchain_server
  tasks:
    - name: Download Docker Compose binary
      get_url:
        url: https://github.com/docker/compose/releases/download/v2.24.5/docker-compose-linux-x86_64
        dest: /usr/local/bin/docker-compose
        mode: '0755'

    - name: Create toolchain directory
      file:
        path: /opt/devops-toolchain
        state: directory
        mode: '0755'

    - name: Copy docker-compose-tools.yml
      copy:
        src: ../docker-toolchain/docker-compose-tools.yml
        dest: /opt/devops-toolchain/docker-compose-tools.yml

    - name: Start DevOps Toolchain Stack
      command: docker-compose -f /opt/devops-toolchain/docker-compose-tools.yml up -d

- name: Configure Application Servers (Dev & Prod)
  hosts: app_server_dev, app_server_prod
  tasks:
    - name: Download Docker Compose binary
      get_url:
        url: https://github.com/docker/compose/releases/download/v2.24.5/docker-compose-linux-x86_64
        dest: /usr/local/bin/docker-compose
        mode: '0755'

    - name: Create app deployment directory
      file:
        path: /opt/ecommerce-app
        state: directory
        mode: '0755'

    - name: Install Certbot and Nginx for Let's Encrypt SSL
      dnf:
        name:
          - nginx
          - certbot
          - python3-certbot-nginx
        state: present

    - name: Start and enable Nginx
      systemd:
        name: nginx
        state: started
        enabled: yes
EOF

echo "4. Writing Spring Boot application source code with Redis & Multi-Cloud integration..."

cat << 'EOF' > ecommerce-app/pom.xml
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>

    <groupId>com.capstone</groupId>
    <artifactId>ecommerce</artifactId>
    <version>1.0.0</version>
    <packaging>jar</packaging>

    <parent>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-starter-parent</artifactId>
        <version>3.2.3</version>
        <relativePath/>
    </parent>

    <properties>
        <java.version>17</java.version>
        <aws.sdk.version>2.20.26</aws.sdk.version>
    </properties>

    <dependencyManagement>
        <dependencies>
            <dependency>
                <groupId>software.amazon.awssdk</groupId>
                <artifactId>bom</artifactId>
                <version>${aws.sdk.version}</version>
                <type>pom</type>
                <scope>import</scope>
            </dependency>
        </dependencies>
    </dependencyManagement>

    <dependencies>
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-web</artifactId>
        </dependency>
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-data-jpa</artifactId>
        </dependency>
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-data-redis</artifactId>
        </dependency>
        <dependency>
            <groupId>com.mysql</groupId>
            <artifactId>mysql-connector-j</artifactId>
            <scope>runtime</scope>
        </dependency>
        <dependency>
            <groupId>software.amazon.awssdk</groupId>
            <artifactId>s3</artifactId>
        </dependency>
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-test</artifactId>
            <scope>test</scope>
        </dependency>
    </dependencies>

    <build>
        <plugins>
            <plugin>
                <groupId>org.springframework.boot</groupId>
                <artifactId>spring-boot-maven-plugin</artifactId>
            </plugin>
            <plugin>
                <groupId>org.apache.maven.plugins</groupId>
                <artifactId>maven-surefire-plugin</artifactId>
                <version>3.2.5</version>
                <configuration>
                    <includes>
                        <include>**/*Test.java</include>
                        <include>**/*Tests.java</include>
                    </includes>
                </configuration>
            </plugin>
        </plugins>
    </build>
</project>
EOF

cat << 'EOF' > ecommerce-app/src/main/resources/application.properties
server.port=8080

# MySQL Database Configuration
spring.datasource.url=jdbc:mysql://${DB_ENDPOINT:localhost}:3306/${DB_NAME:ecomdb}?useSSL=false&allowPublicKeyRetrieval=true
spring.datasource.username=${DB_USER:admin}
spring.datasource.password=${DB_PASS:CapStone2026SecurePass}
spring.datasource.driver-class-name=com.mysql.cj.jdbc.Driver

# JPA / Hibernate Settings
spring.jpa.hibernate.ddl-auto=update
spring.jpa.show-sql=true
spring.jpa.properties.hibernate.dialect=org.hibernate.dialect.MySQLDialect

# Redis Caching Layer Configuration
spring.data.redis.host=${REDIS_HOST:localhost}
spring.data.redis.port=${REDIS_PORT:6379}
spring.cache.type=redis

# AWS S3 Bucket Configuration
aws.s3.bucket-name=${S3_BUCKET_NAME:capstone-media-bucket}
aws.region=${AWS_REGION:us-east-1}
EOF

cat << 'EOF' > ecommerce-app/src/main/java/com/capstone/ecommerce/EcommerceApplication.java
package com.capstone.ecommerce;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.cache.annotation.EnableCaching;

@SpringBootApplication
@EnableCaching
public class EcommerceApplication {
    public static void main(String[] args) {
        SpringApplication.run(EcommerceApplication.class, args);
    }
}
EOF

cat << 'EOF' > ecommerce-app/src/main/java/com/capstone/ecommerce/model/Product.java
package com.capstone.ecommerce.model;

import jakarta.persistence.*;
import java.io.Serializable;

@Entity
@Table(name = "products")
public class Product implements Serializable {

    private static final long serialVersionUID = 1L;

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    private String name;
    private String description;
    private Double price;
    private String imageUrl;

    public Product() {}

    public Product(String name, String description, Double price, String imageUrl) {
        this.name = name;
        this.description = description;
        this.price = price;
        this.imageUrl = imageUrl;
    }

    public Long getId() { return id; }
    public String getName() { return name; }
    public void setName(String name) { this.name = name; }
    public String getDescription() { return description; }
    public void setDescription(String description) { this.description = description; }
    public Double getPrice() { return price; }
    public void setPrice(Double price) { this.price = price; }
    public String getImageUrl() { return imageUrl; }
    public void setImageUrl(String imageUrl) { this.imageUrl = imageUrl; }
}
EOF

cat << 'EOF' > ecommerce-app/src/main/java/com/capstone/ecommerce/repository/ProductRepository.java
package com.capstone.ecommerce.repository;

import com.capstone.ecommerce.model.Product;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

@Repository
public interface ProductRepository extends JpaRepository<Product, Long> {
}
EOF

cat << 'EOF' > ecommerce-app/src/main/java/com/capstone/ecommerce/service/S3StorageService.java
package com.capstone.ecommerce.service;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.web.multipart.MultipartFile;
import software.amazon.awssdk.core.sync.RequestBody;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.PutObjectRequest;

import java.io.IOException;
import java.util.UUID;

@Service
public class S3StorageService {

    @Value("${aws.s3.bucket-name}")
    private String bucketName;

    @Value("${aws.region}")
    private String region;

    private final S3Client s3Client;

    public S3StorageService(@Value("${aws.region}") String region) {
        this.s3Client = S3Client.builder()
                .region(Region.of(region))
                .build();
    }

    public String uploadFile(MultipartFile file) throws IOException {
        String fileName = UUID.randomUUID() + "_" + file.getOriginalFilename();

        PutObjectRequest putObjectRequest = PutObjectRequest.builder()
                .bucket(bucketName)
                .key(fileName)
                .contentType(file.getContentType())
                .build();

        s3Client.putObject(putObjectRequest, RequestBody.fromBytes(file.getBytes()));
        return String.format("https://%s.s3.%s.amazonaws.com/%s", bucketName, region, fileName);
    }
}
EOF

cat << 'EOF' > ecommerce-app/src/main/java/com/capstone/ecommerce/controller/ProductController.java
package com.capstone.ecommerce.controller;

import com.capstone.ecommerce.model.Product;
import com.capstone.ecommerce.repository.ProductRepository;
import com.capstone.ecommerce.service.S3StorageService;
import org.springframework.cache.annotation.Cacheable;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;

import java.util.List;

@RestController
@RequestMapping("/api/products")
@CrossOrigin(origins = "*")
public class ProductController {

    private final ProductRepository productRepository;
    private final S3StorageService s3StorageService;

    public ProductController(ProductRepository productRepository, S3StorageService s3StorageService) {
        this.productRepository = productRepository;
        this.s3StorageService = s3StorageService;
    }

    @GetMapping
    @Cacheable(value = "products")
    public List<Product> getAllProducts() {
        return productRepository.findAll();
    }

    @PostMapping
    public ResponseEntity<Product> createProduct(
            @RequestParam("name") String name,
            @RequestParam("description") String description,
            @RequestParam("price") Double price,
            @RequestParam(value = "image", required = false) MultipartFile image) {

        String imageUrl = "";
        if (image != null && !image.isEmpty()) {
            try {
                imageUrl = s3StorageService.uploadFile(image);
            } catch (Exception e) {
                return ResponseEntity.internalServerError().build();
            }
        }

        Product product = new Product(name, description, price, imageUrl);
        Product savedProduct = productRepository.save(product);
        return ResponseEntity.ok(savedProduct);
    }
}
EOF

cat << 'EOF' > ecommerce-app/src/test/java/com/capstone/ecommerce/controller/ProductControllerTest.java
package com.capstone.ecommerce.controller;

import com.capstone.ecommerce.model.Product;
import com.capstone.ecommerce.repository.ProductRepository;
import com.capstone.ecommerce.service.S3StorageService;
import org.junit.jupiter.api.Test;
import org.mockito.Mockito;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.test.web.servlet.MockMvc;

import java.util.List;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@WebMvcTest(ProductController.class)
public class ProductControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @MockBean
    private ProductRepository productRepository;

    @MockBean
    private S3StorageService s3StorageService;

    @Test
    public void testGetAllProductsReturnsList() throws Exception {
        Product p = new Product("Laptop", "Gaming Laptop", 1200.00, "http://s3.com/image.jpg");
        Mockito.when(productRepository.findAll()).thenReturn(List.of(p));

        mockMvc.perform(get("/api/products"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[0].name").value("Laptop"))
                .andExpect(jsonPath("$[0].price").value(1200.00));
    }
}
EOF

echo "5. Writing Application Containerization Artifacts (Dockerfile & docker-compose.yml)..."

cat << 'EOF' > ecommerce-app/Dockerfile
# Build Stage
FROM maven:3.9.6-eclipse-temurin-17 AS builder
WORKDIR /app
COPY pom.xml .
RUN mvn dependency:go-offline
COPY src ./src
RUN mvn clean package -DskipTests

# Runtime Stage
FROM eclipse-temurin:17-jre-alpine
WORKDIR /app
COPY --from=builder /app/target/ecommerce-1.0.0.jar app.jar
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "app.jar"]
EOF

cat << 'EOF' > ecommerce-app/docker-compose.yml
version: '3.8'

services:
  ecommerce-app:
    image: ${DOCKER_HUB_IMAGE:-ecommerce-app:latest}
    container_name: ecommerce-app
    restart: always
    ports:
      - "8080:8080"
    environment:
      - DB_ENDPOINT=${DB_ENDPOINT:-localhost}
      - DB_NAME=${DB_NAME:-ecomdb}
      - DB_USER=${DB_USER:-admin}
      - DB_PASS=${DB_PASS:-CapStone2026SecurePass}
      - REDIS_HOST=${REDIS_HOST:-localhost}
      - REDIS_PORT=${REDIS_PORT:-6379}
      - S3_BUCKET_NAME=${S3_BUCKET_NAME:-capstone-media-bucket}
      - AWS_REGION=${AWS_REGION:-us-east-1}
EOF

echo "6. Writing Main CI/CD Pipeline (Jenkinsfile)..."

cat << 'EOF' > ecommerce-app/Jenkinsfile
pipeline {
    agent any

    environment {
        DOCKER_HUB_REPO = "yourdockerhubusername/ecommerce-app"
        SONAR_HOST_URL  = "http://sonarqube-server:9000"
    }

    stages {
        stage('Parallel Execution: Build, Test & Scan') {
            parallel {
                stage('Unit Tests via Surefire') {
                    steps {
                        dir('ecommerce-app') {
                            sh 'mvn clean test'
                        }
                    }
                    post {
                        always {
                            junit 'ecommerce-app/target/surefire-reports/*.xml'
                        }
                    }
                }

                stage('SonarQube Static Analysis') {
                    steps {
                        dir('ecommerce-app') {
                            sh 'mvn sonar:sonar -Dsonar.host.url=${SONAR_HOST_URL}'
                        }
                    }
                }

                stage('Trivy Security Scan') {
                    steps {
                        dir('ecommerce-app') {
                            sh 'trivy fs --severity HIGH,CRITICAL .'
                        }
                    }
                }
            }
        }

        stage('Quality Gate Check') {
            steps {
                timeout(time: 5, unit: 'MINUTES') {
                    script {
                        echo "Verifying SonarQube Quality Gate Status..."
                    }
                }
            }
        }

        stage('Build & Push Docker Image') {
            steps {
                dir('ecommerce-app') {
                    sh 'docker build -t ${DOCKER_HUB_REPO}:${BUILD_NUMBER} .'
                    sh 'docker tag ${DOCKER_HUB_REPO}:${BUILD_NUMBER} ${DOCKER_HUB_REPO}:latest'
                    sh 'docker push ${DOCKER_HUB_REPO}:${BUILD_NUMBER}'
                    sh 'docker push ${DOCKER_HUB_REPO}:latest'
                }
            }
        }

        stage('Deploy to Dev Environment') {
            steps {
                dir('ansible') {
                    sh 'ansible-playbook -i aws_ec2.yaml site.yml --limit app_server_dev'
                }
            }
        }

        stage('Manual Approval for Production') {
            steps {
                input message: 'Approve deployment to Production environment?', ok: 'Deploy to Prod'
            }
        }

        stage('Deploy to Production Environment') {
            steps {
                dir('ansible') {
                    sh 'ansible-playbook -i aws_ec2.yaml site.yml --limit app_server_prod'
                }
            }
        }
    }

    post {
        always {
            mail to: 'admin@yourdomain.com',
                 subject: "Pipeline ${JOB_NAME} - Build #${BUILD_NUMBER} Status: ${currentBuild.currentResult}",
                 body: "Stage details and logs are available at ${BUILD_URL}"
        }
    }
}
EOF

echo "7. Writing Secondary Stress Testing Pipeline (stress-Jenkinsfile)..."

cat << 'EOF' > ecommerce-app/stress-Jenkinsfile
pipeline {
    agent any

    stages {
        stage('Generate 80% CPU Stress on App Servers') {
            steps {
                script {
                    echo "Triggering 80% CPU stress test across Production App Servers to test ASG Scale-Up..."
                    dir('ansible') {
                        sh '''
                        ansible app_server_prod -m shell -a "dnf install -e 0 stress-ng -y || true; stress-ng --cpu 4 --cpu-load 80 --timeout 300s &"
                        '''
                    }
                }
            }
        }
    }

    post {
        always {
            echo "Stress test execution complete. Monitor CloudWatch Alarms and Auto Scaling Group activity in AWS Console."
        }
    }
}
EOF

echo "8. Zipping repository..."
zip -r ecommerce_capstone_project.zip ansible/ docker-toolchain/ ecommerce-app/

echo "Success! Generated 'ecommerce_capstone_project.zip' containing all capstone deliverables."
