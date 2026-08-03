"use client";

import { useQuery } from "@tanstack/react-query";
import { api } from "@/lib/api/client";
import { PageHeader } from "@/components/page-header";
import { CustomersTable } from "@/components/customers-table";
import { StatCard } from "@/components/stat-card";
import { inr } from "@/lib/utils";

interface CustomerAnalytics {
  totalCustomers: number;
  activeCustomers: number;
  creditCustomers: number;
  totalOutstanding: number;
  riskDistribution: { low: number; medium: number; high: number; critical: number };
}

export default function CustomersPage() {
  const { data, isLoading } = useQuery({
    queryKey: ["admin", "crm", "analytics"],
    queryFn: () => api.get<CustomerAnalytics>("/admin/crm/customers/analytics"),
  });
  const risk = data?.riskDistribution;
  const atRisk = risk ? risk.high + risk.critical : 0;

  return (
    <>
      <PageHeader title="Customers" description="Directory of all VS Mart customers." />

      <div className="grid grid-cols-2 gap-4 md:grid-cols-4">
        <StatCard label="Total Customers" value={data?.totalCustomers ?? 0} loading={isLoading} />
        <StatCard label="Active" value={data?.activeCustomers ?? 0} accent="green" loading={isLoading} />
        <StatCard label="Credit Customers" value={data?.creditCustomers ?? 0} loading={isLoading} />
        <StatCard
          label="Total Outstanding"
          value={inr(data?.totalOutstanding ?? 0)}
          accent="gold"
          loading={isLoading}
        />
        <StatCard label="Low Risk" value={risk?.low ?? 0} accent="green" loading={isLoading} />
        <StatCard label="Medium Risk" value={risk?.medium ?? 0} accent="gold" loading={isLoading} />
        <StatCard label="High / Critical" value={atRisk} accent="red" loading={isLoading} />
        <StatCard
          label="At-Risk Share"
          value={`${data?.totalCustomers ? Math.round((atRisk / data.totalCustomers) * 100) : 0}%`}
          accent="red"
          loading={isLoading}
        />
      </div>

      <CustomersTable basePath="/customers" />
    </>
  );
}
