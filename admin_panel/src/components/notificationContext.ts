import { createContext, useContext } from 'react';

// السياق والخُطّاف في ملف منفصل عن Notification.tsx: قاعدة
// react-refresh/only-export-components تشترط أن يُصدِّر ملف المكوّنات مكوّنات
// فقط، وإلا انكسر التحديث السريع (Fast Refresh) لكل مَن يستورد منه.

export interface NotificationContextType {
    toast: {
        success: (msg: string) => void;
        error: (msg: string) => void;
        info: (msg: string) => void;
    };
    confirm: (msg: string) => Promise<boolean>;
}

export const NotificationContext = createContext<NotificationContextType>({
    toast: { success: () => {}, error: () => {}, info: () => {} },
    confirm: () => Promise.resolve(false),
});

export const useNotification = () => useContext(NotificationContext);
