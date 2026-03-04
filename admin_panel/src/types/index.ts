// User and Auth Models
export interface User {
    id: string;
    name: string;
    email: string;
    phone: string;
    status: 'active' | 'inactive' | 'banned';
    createdAt: string;
    totalOrders: number;
    totalSpent: number;
}

export interface Driver {
    id: string;
    name: string;
    phone: string;
    vehicle: {
        model: string;
        plate: string;
        year: string;
    };
    status: 'online' | 'offline' | 'busy' | 'suspended';
    rating: number;
    totalRides: number;
    walletBalance: number;
    isVerified: boolean;
    createdAt: string;
}

// Order Models
export type OrderStatus = 'pending' | 'accepted' | 'in-progress' | 'completed' | 'cancelled';

export interface Order {
    id: string;
    customerId: string;
    driverId?: string;
    status: OrderStatus;
    type: string;
    amount: number;
    paymentMethod: 'cash' | 'card' | 'wallet';
    paymentStatus: 'pending' | 'paid' | 'failed';
    pickupLocation: { lat: number; lng: number; address: string };
    dropoffLocation: { lat: number; lng: number; address: string };
    createdAt: string;
    completedAt?: string;
    notes?: string;
}

// Financial Models
export interface Transaction {
    id: string;
    type: 'payment_received' | 'driver_payout' | 'commission_deducted' | 'refund';
    amount: number;
    currency: string;
    relatedOrderId?: string;
    userId?: string;
    date: string;
    status: 'completed' | 'pending' | 'failed';
}

// Support Models
export interface Ticket {
    id: string;
    userId: string;
    userType: 'client' | 'driver';
    subject: string;
    description: string;
    status: 'open' | 'in-progress' | 'closed';
    priority: 'low' | 'medium' | 'high' | 'critical';
    createdAt: string;
    updatedAt: string;
}

// Marketing Models
export interface Coupon {
    id: string;
    code: string;
    type: 'percentage' | 'fixed';
    value: number;
    maxDiscount?: number;
    usageCount: number;
    maxUsage: number;
    status: 'active' | 'expired' | 'disabled';
    expiryDate: string;
    createdAt: string;
}

// Admin / Roles
export interface AdminUser {
    id: string;
    name: string;
    email: string;
    role: 'Super Admin' | 'Accountant' | 'Marketer' | 'Support';
    status: 'active' | 'inactive';
    lastLogin?: string;
}

// Account Deletion Requests
export interface DeletionRequest {
    id: string;
    userId: string;
    userType: 'client' | 'driver';
    reason: string;
    status: 'pending' | 'deleted' | 'rejected';
    requestDate: string;
    resolvedDate?: string;
    adminNotes?: string;
}
