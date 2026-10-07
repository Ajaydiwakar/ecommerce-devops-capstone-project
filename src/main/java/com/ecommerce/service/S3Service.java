package com.ecommerce.service;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import software.amazon.awssdk.auth.credentials.DefaultCredentialsProvider;
import software.amazon.awssdk.core.exception.SdkException;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.s3.presigner.S3Presigner;
import software.amazon.awssdk.services.s3.presigner.model.GetObjectPresignRequest;
import software.amazon.awssdk.services.s3.model.GetObjectRequest;

import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.time.Duration;

@Service
public class S3Service {

    @Value("${aws.s3.bucket}")
    private String bucketName;

    // Uses the EC2 instance's IAM role - no hardcoded access keys
    private final S3Presigner presigner = S3Presigner.builder()
            .region(Region.US_EAST_1)
            .credentialsProvider(DefaultCredentialsProvider.create())
            .build();

    public String getImageUrl(String imageKey) {
        if (imageKey == null || imageKey.isEmpty()) {
            return null;
        }

        try {
            // If AWS credentials are not configured, return a safe mock image URL instead of crashing
            if (System.getenv("AWS_ACCESS_KEY_ID") == null && System.getProperty("aws.accessKeyId") == null) {
                return "https://placehold.co/600x400/0d6efd/ffffff?text=" +
                        URLEncoder.encode(imageKey, StandardCharsets.UTF_8);
            }

            GetObjectRequest getObjectRequest = GetObjectRequest.builder()
                    .bucket(bucketName)
                    .key(imageKey)
                    .build();

            // Builds a pre-signed GET URL valid for 10 minutes
            GetObjectPresignRequest presignRequest = GetObjectPresignRequest.builder()
                    .signatureDuration(Duration.ofMinutes(10))
                    .getObjectRequest(getObjectRequest)
                    .build();

            return presigner.presignGetObject(presignRequest).url().toString();
        } catch (SdkException e) {
            return "https://placehold.co/600x400/0d6efd/ffffff?text=" +
                    URLEncoder.encode(imageKey, StandardCharsets.UTF_8);
        }
    }
}