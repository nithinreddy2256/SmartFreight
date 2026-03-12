package com.smartfreight.common.util;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.SerializationFeature;
import com.fasterxml.jackson.datatype.jsr310.JavaTimeModule;
import com.smartfreight.common.exceptions.SmartFreightException;

/**
 * Utility for JSON serialization/deserialization of events and DTOs.
 *
 * <p>Provides a pre-configured ObjectMapper with Java 8 time support
 * for use in contexts without Spring (Lambda functions, tests).
 * Spring services should inject ObjectMapper as a bean instead.
 */
public final class JsonUtil {

    private static final ObjectMapper MAPPER = new ObjectMapper()
            .registerModule(new JavaTimeModule())
            .disable(SerializationFeature.WRITE_DATES_AS_TIMESTAMPS);

    private JsonUtil() {
        // Utility class — no instantiation
    }

    public static String toJson(Object object) {
        try {
            return MAPPER.writeValueAsString(object);
        } catch (JsonProcessingException e) {
            throw new SmartFreightException(
                    "SERIALIZATION_ERROR",
                    "Failed to serialize object to JSON: " + e.getMessage(), e);
        }
    }

    public static <T> T fromJson(String json, Class<T> type) {
        try {
            return MAPPER.readValue(json, type);
        } catch (JsonProcessingException e) {
            throw new SmartFreightException(
                    "DESERIALIZATION_ERROR",
                    "Failed to deserialize JSON to " + type.getSimpleName() + ": " + e.getMessage(), e);
        }
    }

    /** Access the underlying mapper for advanced usage (e.g., readTree). */
    public static ObjectMapper getMapper() {
        return MAPPER;
    }
}
