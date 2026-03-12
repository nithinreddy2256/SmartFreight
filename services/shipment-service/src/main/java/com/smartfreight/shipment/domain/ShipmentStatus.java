package com.smartfreight.shipment.domain;

import com.smartfreight.common.exceptions.BusinessRuleViolationException;

import java.util.EnumSet;
import java.util.Set;

/**
 * Shipment lifecycle states with valid transition enforcement.
 *
 * <p>Valid state machine transitions:
 * <pre>
 * CREATED ──────────────────► CARRIER_ASSIGNED
 *                                    │
 *                                    ▼
 *                              PICKED_UP
 *                                    │
 *                                    ▼
 *                             IN_TRANSIT ──────► EXCEPTION
 *                                    │               │
 *                                    ▼               │
 *                          OUT_FOR_DELIVERY ◄─────────
 *                                    │
 *                                    ▼
 *                               DELIVERED
 *
 * CANCELLED can be reached from: CREATED, CARRIER_ASSIGNED
 * (Cannot cancel a shipment that has already been picked up)
 * </pre>
 */
public enum ShipmentStatus {

    /** Shipment record created, awaiting carrier assignment. */
    CREATED {
        @Override
        public Set<ShipmentStatus> validTransitions() {
            return EnumSet.of(CARRIER_ASSIGNED, CANCELLED);
        }
    },

    /** Carrier has been assigned and confirmed the shipment. */
    CARRIER_ASSIGNED {
        @Override
        public Set<ShipmentStatus> validTransitions() {
            return EnumSet.of(PICKED_UP, CANCELLED);
        }
    },

    /** Carrier has physically picked up the freight. */
    PICKED_UP {
        @Override
        public Set<ShipmentStatus> validTransitions() {
            return EnumSet.of(IN_TRANSIT);
        }
    },

    /** Shipment is moving through the carrier network. */
    IN_TRANSIT {
        @Override
        public Set<ShipmentStatus> validTransitions() {
            return EnumSet.of(OUT_FOR_DELIVERY, EXCEPTION);
        }
    },

    /** Out for final mile delivery. */
    OUT_FOR_DELIVERY {
        @Override
        public Set<ShipmentStatus> validTransitions() {
            return EnumSet.of(DELIVERED, EXCEPTION);
        }
    },

    /** Delivery exception occurred (missed delivery, address issue, damage). */
    EXCEPTION {
        @Override
        public Set<ShipmentStatus> validTransitions() {
            return EnumSet.of(IN_TRANSIT, OUT_FOR_DELIVERY, CANCELLED);
        }
    },

    /** Shipment delivered to consignee. Terminal state. */
    DELIVERED {
        @Override
        public Set<ShipmentStatus> validTransitions() {
            // Terminal state — no valid transitions
            return EnumSet.noneOf(ShipmentStatus.class);
        }
    },

    /** Shipment cancelled. Terminal state. */
    CANCELLED {
        @Override
        public Set<ShipmentStatus> validTransitions() {
            return EnumSet.noneOf(ShipmentStatus.class);
        }
    };

    /**
     * Returns the set of statuses this status can transition to.
     * Implemented by each enum constant.
     */
    public abstract Set<ShipmentStatus> validTransitions();

    /**
     * Validates that transitioning from this status to {@code targetStatus} is allowed.
     *
     * @param shipmentId  for error message context
     * @param targetStatus the desired next status
     * @throws BusinessRuleViolationException if the transition is invalid
     */
    public void validateTransitionTo(String shipmentId, ShipmentStatus targetStatus) {
        if (!validTransitions().contains(targetStatus)) {
            throw BusinessRuleViolationException.invalidStatusTransition(
                    shipmentId, this.name(), targetStatus.name());
        }
    }

    /**
     * Returns true if this is a terminal state (no further transitions possible).
     */
    public boolean isTerminal() {
        return validTransitions().isEmpty();
    }
}
