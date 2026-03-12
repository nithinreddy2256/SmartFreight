package com.smartfreight.shipment.config;

import org.springframework.core.convert.converter.Converter;
import org.springframework.security.authentication.AbstractAuthenticationToken;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;

import java.util.Collection;
import java.util.List;
import java.util.stream.Collectors;

/**
 * Converts Cognito JWT to Spring Security authentication token.
 *
 * <p>Cognito issues scopes in the {@code scope} claim as a space-separated string,
 * and custom attributes in the {@code cognito:groups} claim.
 * Spring Security expects authorities in a specific format.
 *
 * <p>Scope mapping:
 * <pre>
 * JWT claim "scope": "create:shipments read:shipments update:shipments"
 * → Spring authorities: ["SCOPE_create:shipments", "SCOPE_read:shipments", "SCOPE_update:shipments"]
 * </pre>
 */
public class CognitoJwtAuthenticationConverter
        implements Converter<Jwt, AbstractAuthenticationToken> {

    @Override
    public AbstractAuthenticationToken convert(Jwt jwt) {
        Collection<SimpleGrantedAuthority> authorities = extractAuthorities(jwt);
        return new JwtAuthenticationToken(jwt, authorities, jwt.getSubject());
    }

    private Collection<SimpleGrantedAuthority> extractAuthorities(Jwt jwt) {
        // Extract scopes from the "scope" claim (Cognito OAuth2 client credentials)
        String scopeClaim = jwt.getClaimAsString("scope");
        if (scopeClaim == null || scopeClaim.isBlank()) {
            return List.of();
        }
        return List.of(scopeClaim.split(" ")).stream()
                .filter(scope -> !scope.isBlank())
                .map(scope -> new SimpleGrantedAuthority("SCOPE_" + scope))
                .collect(Collectors.toList());
    }
}
