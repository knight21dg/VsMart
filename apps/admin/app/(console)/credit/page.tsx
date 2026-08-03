"use client";

import * as React from "react";
import { Info } from "lucide-react";
import { PageHeader } from "@/components/page-header";
import { CustomersTable } from "@/components/customers-table";
import {
  CreditApplicationsTab,
  PendingApplicationsBadge,
} from "@/components/credit-applications";
import { Card } from "@/components/ui/card";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";

export default function CreditPage() {
  const [tab, setTab] = React.useState("applications");
  return (
    <>
      <PageHeader
        title="Credit Management"
        description="Review credit applications, then manage the accounts they open."
      />
      <Card className="flex items-start gap-3 border-primary/20 bg-primary/5 p-4 text-sm">
        <Info className="mt-0.5 size-4 shrink-0 text-primary" />
        <p className="text-muted-foreground">
          A customer&apos;s credit line is opened by approving their application with an
          explicit limit — KYC approval verifies identity only and does not grant credit.
          Limits, freeze and status controls for an existing account live on each
          customer&apos;s page. Lending of record runs through a regulated partner (NBFC/bank)
          under the LSP model — these controls manage VS Mart&apos;s servicing view, not
          on-book lending.
        </p>
      </Card>

      <Tabs value={tab} onValueChange={setTab}>
        <TabsList>
          <TabsTrigger value="applications" className="gap-2">
            Applications
            <PendingApplicationsBadge />
          </TabsTrigger>
          <TabsTrigger value="accounts">Accounts</TabsTrigger>
        </TabsList>
        <TabsContent value="applications">
          <CreditApplicationsTab />
        </TabsContent>
        <TabsContent value="accounts">
          <CustomersTable basePath="/customers" />
        </TabsContent>
      </Tabs>
    </>
  );
}
