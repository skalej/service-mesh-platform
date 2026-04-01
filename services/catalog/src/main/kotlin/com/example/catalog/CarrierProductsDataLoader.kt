package com.example.catalog

import com.example.catalog.generated.types.Product
import com.netflix.graphql.dgs.DgsDataLoader
import org.dataloader.MappedBatchLoader
import java.util.concurrent.CompletableFuture
import java.util.concurrent.CompletionStage

@DgsDataLoader(name = "carrierProducts")
class CarrierProductsDataLoader(
    private val store: ProductStore,
) : MappedBatchLoader<String, List<Product>> {
    // Called ONCE per request with ALL carrier ids collected during field resolution.
    // This is where N+1 becomes 1: instead of 3 separate productsByCarrier() calls,
    // DataLoader batches them into a single call here.
    override fun load(carrierIds: Set<String>): CompletionStage<Map<String, List<Product>>> =
        CompletableFuture.supplyAsync {
            store.productsByCarriers(carrierIds)
        }
}
