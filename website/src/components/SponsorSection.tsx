import { useState, useEffect, useRef, useCallback } from "react";
import { motion, AnimatePresence } from "framer-motion";
import { Heart, Loader2, CheckCircle2, X, RefreshCw } from "lucide-react";
import { QRCodeSVG } from "qrcode.react";
import { useLocale } from "@/lib/i18n";

/* ============================================================
   SponsorSection — Free-amount payment (zerx pay gateway)
   - User picks a preset tier or enters a custom amount.
   - POST /api/pay/create -> WeChat codeUrl, rendered as QR.
   - Polls /api/pay/query until status === "paid".
   ============================================================ */

interface SponsorSectionProps {
  fullPage?: boolean;
}

// Preset amounts in yuan.
const PRESET_AMOUNTS = [5, 15, 30, 66, 128];

type PayState =
  | { phase: "idle" }
  | { phase: "creating" }
  | { phase: "pending"; codeUrl: string; outTradeNo: string }
  | { phase: "paid" }
  | { phase: "error"; message: string };

// Poll config.
const POLL_INTERVAL = 2500;
const POLL_TIMEOUT = 5 * 60 * 1000; // 5 minutes

export default function SponsorSection({
  fullPage = false,
}: SponsorSectionProps) {
  const { t } = useLocale();

  const [selected, setSelected] = useState<number>(PRESET_AMOUNTS[1]!);
  const [custom, setCustom] = useState<string>("");
  const [pay, setPay] = useState<PayState>({ phase: "idle" });

  // Effective amount in yuan (custom overrides preset when valid).
  const customNum = parseFloat(custom);
  const amountYuan =
    custom.trim() !== "" && Number.isFinite(customNum) && customNum > 0
      ? customNum
      : selected;
  const amountValid = Number.isFinite(amountYuan) && amountYuan >= 1;

  const pollTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const pollDeadline = useRef<number>(0);

  const stopPolling = useCallback(() => {
    if (pollTimer.current) {
      clearTimeout(pollTimer.current);
      pollTimer.current = null;
    }
  }, []);

  useEffect(() => () => stopPolling(), [stopPolling]);

  const poll = useCallback(
    (outTradeNo: string) => {
      const tick = async () => {
        if (Date.now() > pollDeadline.current) {
          stopPolling();
          setPay({ phase: "error", message: t("sponsor.pay.timeout") });
          return;
        }
        try {
          const res = await fetch(
            `/api/pay/status?outTradeNo=${encodeURIComponent(outTradeNo)}`,
          );
          if (res.ok) {
            const data = (await res.json()) as { paid?: boolean };
            if (data.paid) {
              stopPolling();
              setPay({ phase: "paid" });
              return;
            }
          }
        } catch {
          // transient — keep polling
        }
        pollTimer.current = setTimeout(tick, POLL_INTERVAL);
      };
      pollTimer.current = setTimeout(tick, POLL_INTERVAL);
    },
    [stopPolling, t],
  );

  const startPayment = useCallback(async () => {
    if (!amountValid) return;
    setPay({ phase: "creating" });
    try {
      const res = await fetch("/api/pay/create", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          amountCents: Math.round(amountYuan * 100),
          subject: "Support FluxDown",
        }),
      });
      if (!res.ok) {
        const data = (await res.json().catch(() => ({}))) as { error?: string };
        setPay({
          phase: "error",
          message:
            res.status === 503
              ? t("sponsor.pay.unavailable")
              : data.error || t("sponsor.pay.failed"),
        });
        return;
      }
      const data = (await res.json()) as {
        codeUrl: string;
        outTradeNo: string;
      };
      if (!data.codeUrl || !data.outTradeNo) {
        setPay({ phase: "error", message: t("sponsor.pay.failed") });
        return;
      }
      pollDeadline.current = Date.now() + POLL_TIMEOUT;
      setPay({
        phase: "pending",
        codeUrl: data.codeUrl,
        outTradeNo: data.outTradeNo,
      });
      poll(data.outTradeNo);
    } catch {
      setPay({ phase: "error", message: t("sponsor.pay.failed") });
    }
  }, [amountValid, amountYuan, poll, t]);

  const closeModal = useCallback(() => {
    stopPolling();
    setPay({ phase: "idle" });
  }, [stopPolling]);

  return (
    <section
      id="sponsor"
      className={`relative bg-dark-bg overflow-hidden ${fullPage ? "pt-32 sm:pt-40 pb-20 sm:pb-28" : "py-20 sm:py-28"}`}
    >
      {/* Background decorative elements */}
      <div className="absolute inset-0 pointer-events-none">
        <div className="absolute top-1/4 left-0 w-72 h-72 bg-pink-500/[0.03] blur-[100px] rounded-full" />
        <div className="absolute bottom-1/4 right-0 w-72 h-72 bg-brand-sky/[0.03] blur-[100px] rounded-full" />
      </div>

      <div className="relative mx-auto max-w-2xl px-4 sm:px-6 lg:px-8">
        {/* ── Section header ─────────────────────────────── */}
        <motion.div
          className="text-center mb-12"
          initial={{ opacity: 0, y: 24 }}
          whileInView={{ opacity: 1, y: 0 }}
          viewport={{ once: true, amount: 0.3 }}
          transition={{ duration: 0.5 }}
        >
          <motion.div
            className="inline-flex items-center gap-2 px-3.5 py-1.5 rounded-full border border-pink-500/20 bg-pink-500/5 mb-6"
            initial={{ opacity: 0, scale: 0.9 }}
            whileInView={{ opacity: 1, scale: 1 }}
            viewport={{ once: true }}
            transition={{ duration: 0.4 }}
          >
            <Heart className="w-3.5 h-3.5 text-pink-400" />
            <span className="text-xs font-medium text-pink-400 tracking-wide">
              {t("sponsor.badge")}
            </span>
          </motion.div>

          <h2 className="text-3xl sm:text-4xl font-bold tracking-tight text-dark-text">
            {t("sponsor.title")}
            <span className="bg-gradient-to-r from-pink-400 via-brand-sky to-brand-cyan bg-clip-text text-transparent">
              {t("sponsor.titleHighlight")}
            </span>
          </h2>

          <p className="mt-4 text-sm sm:text-base text-dark-text-secondary max-w-xl mx-auto leading-relaxed">
            {t("sponsor.subtitle")}
          </p>
        </motion.div>

        {/* ── Payment card ───────────────────────────────── */}
        <motion.div
          className="rounded-2xl border border-dark-border/50 bg-dark-surface1/60 p-6 sm:p-8 backdrop-blur-sm"
          initial={{ opacity: 0, y: 20 }}
          whileInView={{ opacity: 1, y: 0 }}
          viewport={{ once: true, amount: 0.2 }}
          transition={{ duration: 0.5, delay: 0.1 }}
        >
          {/* Preset amount tiers */}
          <div className="grid grid-cols-3 sm:grid-cols-5 gap-2.5 mb-5">
            {PRESET_AMOUNTS.map((amt) => {
              const active = custom.trim() === "" && selected === amt;
              return (
                <button
                  key={amt}
                  type="button"
                  onClick={() => {
                    setSelected(amt);
                    setCustom("");
                  }}
                  className={`py-3 rounded-xl border text-sm font-semibold transition-all duration-200 ${
                    active
                      ? "border-brand-sky bg-brand-sky/10 text-brand-sky"
                      : "border-dark-border/50 bg-dark-surface2/40 text-dark-text-secondary hover:border-dark-border hover:text-dark-text"
                  }`}
                >
                  ¥{amt}
                </button>
              );
            })}
          </div>

          {/* Custom amount */}
          <div className="relative mb-6">
            <span className="absolute left-4 top-1/2 -translate-y-1/2 text-dark-text-muted text-sm">
              ¥
            </span>
            <input
              type="number"
              min={1}
              step={1}
              inputMode="decimal"
              value={custom}
              onChange={(e) => setCustom(e.target.value)}
              placeholder={t("sponsor.pay.customPlaceholder")}
              className="w-full pl-8 pr-4 py-3 rounded-xl border border-dark-border/50 bg-dark-surface2/40 text-dark-text text-sm placeholder:text-dark-text-muted focus:outline-none focus:border-brand-sky/60 focus:ring-1 focus:ring-brand-sky/30 transition-all duration-200"
            />
          </div>

          {/* Pay button */}
          <button
            type="button"
            onClick={startPayment}
            disabled={!amountValid || pay.phase === "creating"}
            className="group w-full inline-flex items-center justify-center gap-2.5 px-7 py-3.5 rounded-xl bg-gradient-to-r from-pink-500 to-rose-500 text-white font-semibold text-sm tracking-wide shadow-lg shadow-pink-500/20 hover:shadow-xl hover:shadow-pink-500/30 hover:from-pink-600 hover:to-rose-600 transition-all duration-300 hover:scale-[1.02] active:scale-[0.98] disabled:opacity-50 disabled:cursor-not-allowed disabled:hover:scale-100"
          >
            {pay.phase === "creating" ? (
              <Loader2 className="w-4 h-4 animate-spin" />
            ) : (
              <Heart className="w-4 h-4 transition-transform duration-300 group-hover:scale-110" />
            )}
            {t("sponsor.pay.cta")}
            {amountValid && (
              <span className="opacity-80">· ¥{amountYuan}</span>
            )}
          </button>

          <p className="mt-3 text-center text-xs text-dark-text-muted">
            {t("sponsor.ctaHint")}
          </p>
        </motion.div>
      </div>

      {/* ── Payment modal (QR + status) ──────────────────── */}
      <AnimatePresence>
        {(pay.phase === "pending" ||
          pay.phase === "paid" ||
          pay.phase === "error") && (
          <motion.div
            className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/60 backdrop-blur-sm"
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            onClick={closeModal}
          >
            <motion.div
              className="relative w-full max-w-sm rounded-2xl border border-dark-border/60 bg-dark-surface1 p-7 text-center"
              initial={{ opacity: 0, scale: 0.95, y: 12 }}
              animate={{ opacity: 1, scale: 1, y: 0 }}
              exit={{ opacity: 0, scale: 0.95, y: 12 }}
              transition={{ duration: 0.2 }}
              onClick={(e) => e.stopPropagation()}
            >
              <button
                type="button"
                onClick={closeModal}
                className="absolute right-4 top-4 text-dark-text-muted hover:text-dark-text transition-colors"
                aria-label="Close"
              >
                <X className="w-4 h-4" />
              </button>

              {pay.phase === "pending" && (
                <>
                  <h3 className="text-base font-semibold text-dark-text mb-1">
                    {t("sponsor.pay.scanTitle")}
                  </h3>
                  <p className="text-xs text-dark-text-muted mb-5">
                    {t("sponsor.pay.scanHint")}
                  </p>
                  <div className="inline-flex p-4 rounded-xl bg-white mb-5">
                    <QRCodeSVG value={pay.codeUrl} size={200} level="M" />
                  </div>
                  <div className="flex items-center justify-center gap-2 text-xs text-dark-text-secondary">
                    <Loader2 className="w-3.5 h-3.5 animate-spin" />
                    {t("sponsor.pay.waiting")}
                  </div>
                </>
              )}

              {pay.phase === "paid" && (
                <div className="py-4">
                  <div className="inline-flex items-center justify-center w-16 h-16 rounded-full bg-emerald-500/10 mb-4">
                    <CheckCircle2 className="w-9 h-9 text-emerald-400" />
                  </div>
                  <h3 className="text-lg font-semibold text-dark-text mb-1">
                    {t("sponsor.pay.thanksTitle")}
                  </h3>
                  <p className="text-sm text-dark-text-secondary">
                    {t("sponsor.pay.thanksBody")}
                  </p>
                </div>
              )}

              {pay.phase === "error" && (
                <div className="py-4">
                  <h3 className="text-base font-semibold text-dark-text mb-2">
                    {t("sponsor.pay.errorTitle")}
                  </h3>
                  <p className="text-sm text-dark-text-secondary mb-5">
                    {pay.message}
                  </p>
                  <button
                    type="button"
                    onClick={() => {
                      setPay({ phase: "idle" });
                      startPayment();
                    }}
                    className="inline-flex items-center gap-2 px-5 py-2.5 rounded-lg border border-dark-border/60 text-sm text-dark-text hover:bg-dark-surface2 transition-colors"
                  >
                    <RefreshCw className="w-3.5 h-3.5" />
                    {t("sponsor.pay.retry")}
                  </button>
                </div>
              )}
            </motion.div>
          </motion.div>
        )}
      </AnimatePresence>
    </section>
  );
}
