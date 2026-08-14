/**
 * Regression: the till close must SHOW the day closing, not swallow it.
 *
 * `/store/pos/session/close` answers with expected vs counted cash, the variance,
 * the tender split and the transaction count. The client used to discard the whole
 * response — `onDone` closed the dialog and invalidated the session query, so the
 * cashier got a "Till closed" toast and nothing else, while the count panel
 * promised "The variance against expected cash is shown after closing".
 *
 * These assert the rendered outcome rather than the call, because the old code
 * DID call the endpoint correctly and DID resolve successfully. Only the UI was
 * wrong, so only a UI assertion can fail against it.
 */
import * as React from "react";
import { describe, expect, it, vi, beforeEach } from "vitest";
import { render, screen, waitFor } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import userEvent from "@testing-library/user-event";

const post = vi.fn();
vi.mock("@/lib/api/hooks", async () => {
  const actual = await vi.importActual<typeof import("@/lib/api/hooks")>("@/lib/api/hooks");
  return { ...actual, api: { post: (...a: unknown[]) => post(...a) } };
});
vi.mock("sonner", () => ({ toast: { success: vi.fn(), error: vi.fn() } }));

import { CloseSession } from "@/components/pos/close-session";

const CLOSING = {
  expectedCash: 12500,
  countedCash: 12250,
  variance: -250,
  totalSales: 18400,
  cashSales: 12000,
  upiSales: 4400,
  cardSales: 2000,
  creditSales: 0,
  transactionCount: 37,
};

function mount(onClosed = vi.fn()) {
  const qc = new QueryClient({ defaultOptions: { mutations: { retry: false } } });
  return {
    onClosed,
    ...render(
      <QueryClientProvider client={qc}>
        <CloseSession onClosed={onClosed} />
      </QueryClientProvider>,
    ),
  };
}

/** Open the count dialog, key one ₹500 note, and press Close till. */
async function closeTill(user: ReturnType<typeof userEvent.setup>) {
  await user.click(screen.getByRole("button", { name: /close till/i }));
  await user.type(screen.getByLabelText("₹500"), "1");
  await user.click(screen.getByRole("button", { name: /^close till$/i }));
}

describe("CloseSession", () => {
  beforeEach(() => {
    post.mockReset();
    post.mockResolvedValue(CLOSING);
  });

  it("shows the cash variance after closing", async () => {
    const user = userEvent.setup();
    mount();
    await closeTill(user);

    // The number the whole counting exercise exists to produce.
    expect(await screen.findByText(/cash variance/i)).toBeTruthy();
    expect(screen.getByText(/₹250\.00 short/i)).toBeTruthy();
  });

  it("labels an over-count as over rather than short", async () => {
    post.mockResolvedValue({ ...CLOSING, countedCash: 12800, variance: 300 });
    const user = userEvent.setup();
    mount();
    await closeTill(user);

    expect(await screen.findByText(/₹300\.00 over/i)).toBeTruthy();
  });

  it("says Balanced when the drawer reconciles exactly", async () => {
    post.mockResolvedValue({ ...CLOSING, countedCash: 12500, variance: 0 });
    const user = userEvent.setup();
    mount();
    await closeTill(user);

    expect(await screen.findByText(/balanced/i)).toBeTruthy();
  });

  it("reports expected vs counted cash and the tender split", async () => {
    const user = userEvent.setup();
    mount();
    await closeTill(user);

    await screen.findByText(/cash variance/i);
    expect(screen.getByText("Expected cash")).toBeTruthy();
    expect(screen.getByText("₹12,500.00")).toBeTruthy();
    expect(screen.getByText("₹12,250.00")).toBeTruthy();
    expect(screen.getByText("UPI sales")).toBeTruthy();
    expect(screen.getByText(/37 transactions/)).toBeTruthy();
  });

  it("only resets the till once the summary is acknowledged", async () => {
    const user = userEvent.setup();
    const { onClosed } = mount();
    await closeTill(user);
    await screen.findByText(/cash variance/i);

    // Invalidating the session straight away would unmount this dialog and take
    // the variance with it — the exact bug. It must wait for Done.
    expect(onClosed).not.toHaveBeenCalled();
    await user.click(screen.getByRole("button", { name: /done/i }));
    await waitFor(() => expect(onClosed).toHaveBeenCalledTimes(1));
  });

  it("sends the counted total and keeps the drawer breakdown in the note", async () => {
    const user = userEvent.setup();
    mount();
    await closeTill(user);

    await waitFor(() => expect(post).toHaveBeenCalled());
    const [path, body] = post.mock.calls[0] as [string, { countedCash: number; notes: string }];
    expect(path).toBe("/store/pos/session/close");
    expect(body.countedCash).toBe(500);
    expect(body.notes).toContain("500x1");
  });

  it("keeps the count dialog open and usable when the close fails", async () => {
    post.mockRejectedValue(new Error("network"));
    const user = userEvent.setup();
    const { onClosed } = mount();
    await closeTill(user);

    // A failed close must not reset the till or claim a summary it never got.
    await waitFor(() => expect(post).toHaveBeenCalled());
    expect(screen.queryByText(/cash variance/i)).toBeNull();
    expect(onClosed).not.toHaveBeenCalled();
    expect(screen.getByText(/count the drawer/i)).toBeTruthy();
  });
});
