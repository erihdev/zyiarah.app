import { Receipt } from 'lucide-react';
import { metaRows, metaHeadline } from '../utils/serviceMeta.ts';

/// جدول تفصيل الخدمة — **مرآة الويب** لـ ZyiarahServiceMetaView في
/// lib/widgets/service_meta_view.dart.
///
/// **سبب وجوده:** الطلب كان يصل لوحة الويب بمبلغ مجرّد. كم قطعة وما مقاسها؟
/// كم مكيفاً ومن أي نوع؟ أي مواد تنظيف دفعت العميلة ثمنها؟ لا شيء — بينما
/// التطبيق يعرضها كلها. وكتابة `service_meta` بلا قارئ = بيانات ميتة.
export default function ServiceMetaTable({ meta }: { meta: unknown }) {
    const rows = metaRows(meta);
    if (rows.length === 0) return null;
    const headline = metaHeadline(meta);

    return (
        <div className="bg-white border border-slate-200 rounded-2xl p-5">
            <div className="flex items-center gap-2 mb-1">
                <Receipt size={18} className="text-[#660033]" />
                <h4 className="font-black text-slate-800 text-sm">تفصيل الخدمة</h4>
                {headline && <span className="text-xs text-slate-400 font-bold">• {headline}</span>}
            </div>
            <div className="divide-y divide-slate-50 mt-2">
                {rows.map((r, i) => (
                    <div key={i} className="flex items-center gap-3 py-2">
                        <div className="flex-1 min-w-0">
                            <div className="font-bold text-sm text-slate-700 truncate">{r.label}</div>
                            {r.detail ? <div className="text-[11px] text-slate-400">{r.detail}</div> : null}
                        </div>
                        <div className="text-sm font-black text-slate-800 shrink-0">{r.total}</div>
                    </div>
                ))}
            </div>
        </div>
    );
}
