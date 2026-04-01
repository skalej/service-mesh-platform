package graph

import (
	"context"
	"testing"
)

func TestShippingResolver(t *testing.T) {
	r := &Resolver{}
	qr := r.Query()

	info, err := qr.Shipping(context.Background(), "product-123")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if info.Carrier == nil {
		t.Fatal("expected Carrier to be set, got nil")
	}

	if info.Carrier.Name != "FedEx" {
		t.Errorf("expected Carrier.Name 'FedEx', got '%s'", info.Carrier.Name)
	}

	if info.Carrier.EstimatedDays != 3 {
		t.Errorf("expected Carrier.EstimatedDays 3, got %d", info.Carrier.EstimatedDays)
	}
}
