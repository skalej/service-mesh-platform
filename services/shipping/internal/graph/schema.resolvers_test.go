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

	if info.ProductID != "product-123" {
		t.Errorf("expected ProductID 'product-123', got '%s'", info.ProductID)
	}

	if info.EstimatedDays != 3 {
		t.Errorf("expected EstimatedDays 3, got %d", info.EstimatedDays)
	}

	if info.Carrier != "FedEx" {
		t.Errorf("expected Carrier 'FedEx', got '%s'", info.Carrier)
	}
}
