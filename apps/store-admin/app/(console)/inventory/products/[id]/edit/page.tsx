"use client";

import { useParams } from "next/navigation";
import { StoreProductForm } from "../../product-form";

export default function EditProductPage() {
  const { id } = useParams<{ id: string }>();
  return <StoreProductForm productId={id} />;
}
