"use client";

import { useParams } from "next/navigation";
import { StoreFormPage } from "@/components/stores/store-form";

export default function EditStorePage() {
  const { id } = useParams<{ id: string }>();
  return <StoreFormPage storeId={id} />;
}
