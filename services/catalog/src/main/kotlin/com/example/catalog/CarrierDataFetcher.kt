package com.example.catalog

import com.example.catalog.generated.types.Carrier
import com.example.catalog.generated.types.Product
import com.netflix.graphql.dgs.DgsComponent
import com.netflix.graphql.dgs.DgsData
import com.netflix.graphql.dgs.DgsDataFetchingEnvironment
import com.netflix.graphql.dgs.DgsEntityFetcher
import java.util.concurrent.CompletableFuture

@DgsComponent
class CarrierDataFetcher(
    private val store: ProductStore
) {

    // Step 1 — Apollo Router calls _entities with carrier ids.
    // Return a stub with just the id; DgsData below resolves the products field from it.
    @DgsEntityFetcher(name = "Carrier")
    fun resolveCarrier(values: Map<String, Any>): Carrier {
        return Carrier(id = values["id"].toString())
    }

    // Step 2 — DGS calls this for each Carrier stub returned above.
    // This is where the N+1 lives: one call per carrier in the result.
    @DgsData(parentType = "Carrier", field = "products")
    fun products(dfe: DgsDataFetchingEnvironment): CompletableFuture<List<Product>> {
        val carrier = dfe.getSource<Carrier>()
        val loader = dfe.getDataLoader<String, List<Product>>("carrierProducts")
        return loader!!.load(carrier!!.id)
    }

//    @DgsData(parentType = "Carrier", field = "products")
//    fun products(dfe: DgsDataFetchingEnvironment): List<Product> {
//        val carrier = dfe.getSource<Carrier>()
//        return store.productsByCarrier(carrier!!.id!!)
//    }

}