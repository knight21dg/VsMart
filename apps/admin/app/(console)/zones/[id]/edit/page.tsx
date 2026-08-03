"use client";

import { useParams } from "next/navigation";
import { ZoneFormPage } from "@/components/zones/zone-form";

export default function EditZonePage() {
  const { id } = useParams<{ id: string }>();
  return <ZoneFormPage zoneId={id} />;
}
