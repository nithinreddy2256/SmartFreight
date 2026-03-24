package com.smartfreight.document.repository;

import com.smartfreight.document.domain.DocumentMetadata;
import lombok.RequiredArgsConstructor;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Repository;
import software.amazon.awssdk.enhanced.dynamodb.DynamoDbEnhancedClient;
import software.amazon.awssdk.enhanced.dynamodb.DynamoDbIndex;
import software.amazon.awssdk.enhanced.dynamodb.DynamoDbTable;
import software.amazon.awssdk.enhanced.dynamodb.Key;
import software.amazon.awssdk.enhanced.dynamodb.TableSchema;
import software.amazon.awssdk.enhanced.dynamodb.model.QueryConditional;

import java.util.List;
import java.util.Optional;

@Repository
@RequiredArgsConstructor
public class DocumentMetadataRepository {

    private final DynamoDbEnhancedClient dynamoDbEnhancedClient;

    @Value("${aws.dynamodb.document-index-table-name}")
    private String tableName;

    private DynamoDbTable<DocumentMetadata> table() {
        return dynamoDbEnhancedClient.table(tableName, TableSchema.fromBean(DocumentMetadata.class));
    }

    public void save(DocumentMetadata metadata) {
        table().putItem(metadata);
    }

    public Optional<DocumentMetadata> findById(String documentId) {
        var item = table().getItem(Key.builder().partitionValue(documentId).build());
        return Optional.ofNullable(item);
    }

    public List<DocumentMetadata> findByShipmentId(String shipmentId) {
        DynamoDbIndex<DocumentMetadata> index = table().index("shipmentId-index");
        var condition = QueryConditional.keyEqualTo(Key.builder().partitionValue(shipmentId).build());
        return index.query(condition).stream()
                .flatMap(page -> page.items().stream())
                .toList();
    }

    public void delete(String documentId) {
        table().deleteItem(Key.builder().partitionValue(documentId).build());
    }
}
