package com.smartfreight.carrier.service;

import com.smartfreight.carrier.domain.CarrierRate;
import com.smartfreight.carrier.repository.CarrierRateRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.cache.annotation.CacheEvict;
import org.springframework.cache.annotation.Cacheable;
import org.springframework.stereotype.Service;

import java.math.BigDecimal;
import java.util.Comparator;
import java.util.List;
import java.util.Optional;

/**
 * Carrier rate lookup and quoting service.
 *
 * <p>Results are cached with Caffeine (5-minute TTL) to reduce DynamoDB reads.
 * Rate data is refreshed from carrier APIs every 6 hours by the EventBridge-triggered
 * Lambda carrier-rate-refresh, which evicts the cache after writing.
 *
 * <p>Cache names:
 * <ul>
 *   <li>{@code carrier-rates} — rates for a specific carrier+lane</li>
 *   <li>{@code lane-quotes} — multi-carrier quote results</li>
 * </ul>
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class CarrierRateService {

    private final CarrierRateRepository rateRepository;

    /**
     * Gets the rate card for a specific carrier and lane.
     * Result cached for 5 minutes.
     */
    @Cacheable(value = "carrier-rates", key = "#carrierId + ':' + #laneId")
    public Optional<CarrierRate> getRate(String carrierId, String laneId) {
        log.debug("Cache miss — loading rate from DynamoDB. carrierId={} laneId={}",
                carrierId, laneId);
        return rateRepository.findByCarrierIdAndLaneId(carrierId, laneId);
    }

    /**
     * Gets all active rates for a carrier.
     * Result cached for 5 minutes.
     */
    @Cacheable(value = "carrier-rates", key = "#carrierId + ':all'")
    public List<CarrierRate> getRatesForCarrier(String carrierId) {
        return rateRepository.findAllByCarrierId(carrierId).stream()
                .filter(CarrierRate::isActive)
                .toList();
    }

    /**
     * Multi-carrier rate quote: finds the cheapest carrier for a lane and weight.
     * Queries all active carriers for the lane and returns sorted by total rate.
     *
     * <p>Result cached for 5 minutes by lane + weight bucket.
     */
    @Cacheable(value = "lane-quotes",
               key = "#originState + ':' + #destinationState + ':' + #shipmentType + ':' + #weightBucket(#weightLbs)")
    public List<CarrierRateQuote> getMultiCarrierQuote(String originState, String destinationState,
                                                        String shipmentType, BigDecimal weightLbs) {
        var laneId = originState + "-" + destinationState + "-" + shipmentType;
        var rates = rateRepository.findAllByLaneId(laneId).stream()
                .filter(CarrierRate::isActive)
                .toList();

        return rates.stream()
                .map(rate -> new CarrierRateQuote(
                        rate.getCarrierId(),
                        rate.getCarrierName(),
                        rate.getLaneId(),
                        rate.calculateRate(weightLbs),
                        rate.getTransitDays()
                ))
                .sorted(Comparator.comparing(CarrierRateQuote::totalRate))
                .toList();
    }

    /**
     * Upserts a rate card (called by carrier-rate-refresh Lambda via internal API).
     * Evicts the cache for this carrier to force fresh data on next read.
     */
    @CacheEvict(value = {"carrier-rates", "lane-quotes"}, allEntries = true)
    public void upsertRate(CarrierRate rate) {
        rateRepository.save(rate);
        log.info("Rate updated and cache evicted. carrierId={} laneId={}",
                rate.getCarrierId(), rate.getLaneId());
    }

    /** Buckets weight to the nearest 50 lbs for cache key granularity. */
    private int weightBucket(BigDecimal weightLbs) {
        if (weightLbs == null) return 0;
        return (weightLbs.intValue() / 50) * 50;
    }

    /**
     * Quote result DTO for multi-carrier comparison.
     */
    public record CarrierRateQuote(
            String carrierId,
            String carrierName,
            String laneId,
            BigDecimal totalRate,
            int transitDays
    ) {}
}
