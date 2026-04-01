package com.example.catalog

import com.example.catalog.generated.DgsConstants
import com.example.catalog.generated.types.CreateProductInput
import com.example.catalog.generated.types.Product
import com.example.catalog.generated.types.UpdateProductInput
import com.netflix.graphql.dgs.DgsComponent
import com.netflix.graphql.dgs.DgsMutation
import com.netflix.graphql.dgs.InputArgument

@DgsComponent
class ProductMutationFetcher(
    private val store: ProductStore,
) {
    @DgsMutation(field = DgsConstants.MUTATION.CreateProduct)
    fun createProduct(
        @InputArgument input: CreateProductInput,
    ): Product {
        val product = Product(id = store.nextId(), name = input.name, price = input.price)
        return store.save(product)
    }

    @DgsMutation(field = DgsConstants.MUTATION.UpdateProduct)
    fun updateProduct(
        @InputArgument id: String,
        @InputArgument input: UpdateProductInput,
    ): Product? {
        val existing = store.findById(id) ?: return null
        val updated =
            existing.copy(
                name = input.name ?: existing.name,
                price = input.price ?: existing.price,
            )
        return store.save(updated)
    }

    @DgsMutation(field = DgsConstants.MUTATION.DeleteProduct)
    fun deleteProduct(
        @InputArgument id: String,
    ): Boolean = store.delete(id)
}
