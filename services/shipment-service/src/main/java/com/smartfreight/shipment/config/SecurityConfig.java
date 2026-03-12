package com.smartfreight.shipment.config;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.HttpMethod;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.web.SecurityFilterChain;

/**
 * Spring Security configuration for JWT-based API authentication.
 *
 * <p>Uses Spring Security OAuth2 Resource Server to validate JWTs issued by
 * AWS Cognito. The JWT issuer URI is configured in application.yml:
 * {@code spring.security.oauth2.resourceserver.jwt.issuer-uri}
 *
 * <p>Authorization rules:
 * <ul>
 *   <li>GET /actuator/health — public (for ALB health checks)</li>
 *   <li>GET /actuator/info — public</li>
 *   <li>GET /swagger-ui/** — public (for internal use; restrict in production)</li>
 *   <li>POST /api/shipments — requires SCOPE_create:shipments</li>
 *   <li>GET /api/shipments/** — requires SCOPE_read:shipments</li>
 *   <li>PUT /api/shipments/** — requires SCOPE_update:shipments</li>
 * </ul>
 */
@Configuration
@EnableWebSecurity
public class SecurityConfig {

    @Bean
    public SecurityFilterChain securityFilterChain(HttpSecurity http) throws Exception {
        http
            .csrf(csrf -> csrf.disable())  // Stateless API — no CSRF needed
            .sessionManagement(session ->
                session.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
            .authorizeHttpRequests(auth -> auth
                // ALB health checks — must be public
                .requestMatchers(HttpMethod.GET, "/actuator/health", "/actuator/info").permitAll()
                // API docs — internal use only (would be restricted at network level in prod)
                .requestMatchers("/swagger-ui/**", "/v3/api-docs/**").permitAll()
                // Shipment operations
                .requestMatchers(HttpMethod.POST, "/api/shipments")
                    .hasAuthority("SCOPE_create:shipments")
                .requestMatchers(HttpMethod.GET, "/api/shipments", "/api/shipments/**")
                    .hasAuthority("SCOPE_read:shipments")
                .requestMatchers(HttpMethod.PUT, "/api/shipments/**")
                    .hasAuthority("SCOPE_update:shipments")
                .requestMatchers(HttpMethod.POST, "/api/shipments/*/assign-carrier",
                                               "/api/shipments/*/deliver")
                    .hasAuthority("SCOPE_update:shipments")
                .anyRequest().authenticated()
            )
            .oauth2ResourceServer(oauth2 -> oauth2
                .jwt(jwt -> jwt.jwtAuthenticationConverter(
                    new CognitoJwtAuthenticationConverter()))
            );

        return http.build();
    }
}
