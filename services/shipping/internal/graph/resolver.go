package graph

import "github.com/example/shipping/internal/graph/model"

// Resolver is the root resolver. Add dependencies here (e.g. DB connection).
type Resolver struct{}

// carriers is the in-memory carrier store — shared across all resolvers.
var carriers = map[string]*model.Carrier{
	"fedex": {ID: "fedex", Name: "FedEx", EstimatedDays: 3},
	"ups":   {ID: "ups", Name: "UPS", EstimatedDays: 5},
	"usps":  {ID: "usps", Name: "USPS", EstimatedDays: 7},
}
