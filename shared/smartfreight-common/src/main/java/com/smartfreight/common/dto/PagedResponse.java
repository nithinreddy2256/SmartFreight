package com.smartfreight.common.dto;

import lombok.Builder;
import lombok.Getter;

import java.util.List;

/**
 * Paginated response wrapper for list endpoints.
 *
 * <p>Used for endpoints like GET /api/shipments and GET /api/invoices.
 *
 * @param <T> type of individual items in the page
 */
@Getter
@Builder
public class PagedResponse<T> {

    private final List<T> content;
    private final int page;
    private final int size;
    private final long totalElements;
    private final int totalPages;
    private final boolean first;
    private final boolean last;

    public static <T> PagedResponse<T> from(org.springframework.data.domain.Page<T> page) {
        return PagedResponse.<T>builder()
                .content(page.getContent())
                .page(page.getNumber())
                .size(page.getSize())
                .totalElements(page.getTotalElements())
                .totalPages(page.getTotalPages())
                .first(page.isFirst())
                .last(page.isLast())
                .build();
    }
}
