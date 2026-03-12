package com.smartfreight.carrier.repository;

import com.smartfreight.carrier.domain.CarrierRate;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Repository;
import software.amazon.awssdk.enhanced.dynamodb.DynamoDbEnhancedClient;
import software.amazon.awssdk.enhanced.dynamodb.DynamoDbTable;
import software.amazon.awssdk.enhanced.dynamodb.Key;
import software.amazon.awssdk.enhanced.dynamodb.TableSchema;
import software.amazon.awssdk.enhanced.dynamodb.model.QueryConditional;

import jakarta.annotation.PostConstruct;
import java.util.List;
import java.util.Optional;

/**
 * DynamoDB repository for carrier rate cards using the AWS Enhanced Client.
 *
 * <p>Table: CarrierRateTable (configured in application.yml)
 * <ul>
 *   <li>PK: carrierId, SK: laneId</li>
 *   <li>GSI: laneId-carrierId-index for "all carriers serving a lane"</li>
 * </ul>
 */
@Repository
@RequiredArgsConstructor
public class CarrierRateRepository {

    private final DynamoDbEnhancedClient dynamoDbEnhancedClient;
    private DynamoDbTable<CarrierRate> table;

    // Table name injected from application.yml
    @org.springframework.beans.factory.annotation.Value("${aws.dynamodb.carrier-rate-table-name}")
    private String tableName;

    @PostConstruct
    public void initialize() {
        this.table = dynamoDbEnhancedClient.table(
                tableName, TableSchema.fromBean(CarrierRate.class));
    }

    public Optional<CarrierRate> findByCarrierIdAndLaneId(String carrierId, String laneId) {
        var key = Key.builder()
                .partitionValue(carrierId)
                .sortValue(laneId)
                .build();
        return Optional.ofNullable(table.getItem(key));
    }

    /**
     * Queries all rates for a carrier (partition key query — efficient).
     */
    public List<CarrierRate> findAllByCarrierId(String carrierId) {
        var queryCondition = QueryConditional.keyEqualTo(
                Key.builder().partitionValue(carrierId).build());
        return table.query(queryCondition).items().stream().toList();
    }

    /**
     * Finds all carriers serving a lane via GSI.
     * GSI: laneId-carrierId-index
     */
    public List<CarrierRate> findAllByLaneId(String laneId) {
        var laneIndex = table.index("laneId-carrierId-index");
        var queryCondition = QueryConditional.keyEqualTo(
                Key.builder().partitionValue(laneId).build());
        return laneIndex.query(queryCondition)
                .stream()
                .flatMap(page -> page.items().stream())
                .toList();
    }

    public void save(CarrierRate rate) {
        table.putItem(rate);
    }
}
