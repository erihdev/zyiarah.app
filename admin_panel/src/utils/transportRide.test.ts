import { describe, it, expect } from 'vitest';
import {
  TRANSPORT_LIVE_STATES,
  TRANSPORT_FINAL_STATES,
  transportLegOf,
  transportStateLabel,
  currentTransportLeg,
} from './transportRide';

// `import.meta.glob` لا `node:fs` — القاعدةُ المسجَّلةُ في هذا المستودع
// (لا أنواعَ لـ`node:fs` تحت `tsconfig.app.json`، وقد أعقمَت حارسَين).
const files = import.meta.glob(
  ['../../../functions/transport.js', '../../../lib/utils/transport_ride.dart', '../pages/Orders.tsx'],
  { query: '?raw', import: 'default', eager: true },
) as Record<string, string>;
function read(p: string): string {
  const key = Object.keys(files).find((k) => k.endsWith(p));
  const src = key ? files[key] : '';
  if (!src) throw new Error(`لم يُقرأ ${p}`);
  return src;
}

/** مجموعةٌ من ثابتٍ جافاسكربتيٍّ `Object.freeze([...])` في الخادم. */
function jsSet(src: string, name: string): Set<string> {
  const m = src.match(new RegExp(`const ${name} = Object\\.freeze\\(\\[([^\\]]*)\\]\\)`));
  expect(m, name).not.toBeNull();
  return new Set([...m![1].matchAll(/"(\w+)"/g)].map((x) => x[1]));
}

describe('transportRide — مرآةُ transport_ride.dart وtransport.js', () => {
  it('مجموعتا الحيِّ والنهائيِّ تُساويانِ الخادمَ حرفاً', () => {
    const server = read('/functions/transport.js');
    expect(new Set(TRANSPORT_LIVE_STATES)).toEqual(jsSet(server, 'LIVE_STATES'));
    expect(new Set(TRANSPORT_FINAL_STATES)).toEqual(jsSet(server, 'FINAL_STATES'));
  });

  it('التسمياتُ تُطابقُ المرآةَ الدارتيّةَ حرفاً، ولا لاتينيّةَ فيها', () => {
    const dart = read('/lib/utils/transport_ride.dart');
    const i = dart.indexOf('String transportStateLabel(');
    const body = dart.slice(i, dart.indexOf('\n}', i));
    const dartLabels = new Map(
      [...body.matchAll(/'(\w+)' => '([^']+)'/g)].map((m) => [m[1], m[2]]),
    );
    expect(dartLabels.size).toBeGreaterThan(0);
    for (const [state, label] of dartLabels) {
      expect(transportStateLabel(state), state).toBe(label);
      expect(/[A-Za-z]/.test(label), state).toBe(false);
    }
    expect(transportStateLabel('teleported')).toBe('غير معروفة');
  });

  it('قراءةُ ساقٍ: كاملةٌ، وغائبةٌ null، ومعطوبةٌ null', () => {
    const order = {
      transport: {
        outbound: {
          state: 'accepted',
          driver: { name: 'سالم', phone: '0509', plate: 'أ ب ج 123' },
          eta_minutes: 7,
          error: '',
        },
      },
    };
    expect(transportLegOf(order, 'outbound')).toEqual({
      leg: 'outbound', state: 'accepted', driverName: 'سالم', driverPhone: '0509',
      driverPlate: 'أ ب ج 123', etaMinutes: 7, error: null,
    });
    expect(transportLegOf(order, 'return')).toBeNull();
    expect(transportLegOf({}, 'outbound')).toBeNull();
    expect(transportLegOf({ transport: 'x' }, 'outbound')).toBeNull();
    expect(transportLegOf({ transport: { outbound: { state: '' } } }, 'outbound')).toBeNull();
  });

  it('الساقُ الحاليّةُ: الذهابُ قبلَ الإنجازِ والعودةُ بعدَه', () => {
    const t = { outbound: { state: 'completed' }, return: { state: 'requested' } };
    expect(currentTransportLeg({ status: 'scheduled', transport: t })?.leg).toBe('outbound');
    expect(currentTransportLeg({ status: 'completed', transport: t })?.leg).toBe('return');
    expect(currentTransportLeg({ status: 'completed', transport: { outbound: { state: 'completed' } } })?.leg)
      .toBe('outbound');
    expect(currentTransportLeg({ status: 'pending' })).toBeNull();
  });

  it('الربط: قائمةُ الطلباتِ تَعرضُ الشارةَ من هذه الوحدةِ لا بيدِها', () => {
    const src = read('/pages/Orders.tsx');
    expect(src).toContain("from '../utils/transportRide'");
    expect(src).toContain('currentTransportLeg(');
    expect(src).toContain('transportStateLabel(');
    expect(src).toContain('transportStateClass(');
  });
});
