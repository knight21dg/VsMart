// Shapes returned by the VS Mart API for the customer account area.
//
// The auth/user endpoints render snake_case (they back the Flutter models);
// the catalog/orders endpoints render camelCase. Both are mirrored verbatim
// here so no field silently goes missing.

export interface ApiUser {
  id: string;
  phone: string;
  name: string | null;
  email: string | null;
  role: string;
  avatar_url?: string | null;
  gender?: string | null;
  date_of_birth?: string | null;
  kyc_status?: string | null;
  credit_enabled?: boolean | null;
  created_at?: string | null;
}

export interface AuthTokens {
  access_token: string;
  refresh_token?: string | null;
  expires_at?: string | null;
}

export interface OtpVerifyResponse extends AuthTokens {
  is_new_user?: boolean;
  user: ApiUser;
}

export interface OrderItem {
  id?: string | number;
  name?: string | null;
  productName?: string | null;
  quantity?: number | null;
  price?: number | null;
  imageUrl?: string | null;
}

export interface Order {
  id: string;
  status: string;
  placedAt?: string | null;
  estimatedDelivery?: string | null;
  paymentMethod?: string | null;
  paymentStatus?: string | null;
  total?: number | null;
  creditUsed?: number | null;
  items?: OrderItem[] | null;
}

/** `{ user }` payload of `GET /api/auth/session`. */
export interface SessionResponse {
  user: ApiUser | null;
}
