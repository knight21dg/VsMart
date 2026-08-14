"""VS Mart — machine-readable API response catalog (single source of truth).

Every actionable response (success OR failure) is keyed by a stable CODE that the
frontend branches on to drive the correct UX: toast / banner / dialog / blocker /
navigation / retry / escalation. No generic "Something went wrong" anywhere.

Each entry carries:
  http        HTTP status to return
  success     True for success-coded responses, False for failures
  title       short, human-readable headline
  message     what happened + why, in plain language
  action      what the client should do — {"type": ..., "target"?: ...} or None
              types: navigate | retry | retry_verification | logout |
                     contact_support | refresh | reauth | none
  retryable   may the same call be retried as-is?
  severity    info | success | warning | error | critical
  next_step   guidance toward the next valid action
  module      owning domain (for audit + filtering)
  security    True → also raised as a security event in the audit trail
  risk        True → also raised as a risk event (credit/fraud signals)

Add codes here only; views/services reference them by key via core.app_errors.
"""

# ── severities ──
INFO = "info"
SUCCESS = "success"
WARNING = "warning"
ERROR = "error"
CRITICAL = "critical"


# ── action helpers ──
def nav(target):
    return {"type": "navigate", "target": target}


RETRY = {"type": "retry"}
RETRY_VERIFICATION = {"type": "retry_verification"}
LOGOUT = {"type": "logout"}
REAUTH = {"type": "reauth"}
SUPPORT = {"type": "contact_support"}
REFRESH = {"type": "refresh"}


def E(title, message, *, http=400, success=False, action=None, retryable=False,
      severity=WARNING, next_step="", module="system", security=False, risk=False):
    return {
        "http": http, "success": success, "title": title, "message": message,
        "action": action, "retryable": retryable, "severity": severity,
        "next_step": next_step, "module": module, "security": security, "risk": risk,
    }


CATALOG: dict[str, dict] = {

    # ════════════════════════ ACCOUNT / WEB AUTH ════════════════════════
    "LOGIN_OK": E(
        "Welcome Back", "Signed in successfully.",
        http=200, success=True, severity=SUCCESS, module="auth"),
    "INVALID_CREDENTIALS": E(
        "Sign-in Failed", "The email or password is incorrect.",
        http=401, severity=WARNING, retryable=True,
        next_step="Check your email and password, or reset your password.",
        module="auth", security=True),
    "ACCOUNT_DISABLED": E(
        "Account Disabled", "This account has been disabled.",
        http=403, severity=ERROR, next_step="Contact your administrator.",
        module="auth", security=True),
    "AGENT_NOT_REGISTERED": E(
        "Not a Registered Agent",
        "This number isn't registered as a delivery agent.",
        http=404, severity=WARNING,
        next_step="Ask your store to add you as an agent, then try again.",
        module="auth", security=True),
    "PASSWORD_RESET_SENT": E(
        "Check Your Phone", "We've sent a verification code to your phone.",
        http=200, success=True, severity=SUCCESS,
        next_step="Enter the code we texted you to set a new password.", module="auth"),
    "INVALID_RESET_CODE": E(
        "Invalid or Expired Code", "That reset code is invalid or has expired.",
        http=400, severity=WARNING, retryable=True,
        next_step="Request a new reset code.", module="auth"),
    "PASSWORD_RESET_OK": E(
        "Password Updated", "Your password has been changed.",
        http=200, success=True, severity=SUCCESS,
        next_step="Sign in with your new password.", module="auth"),
    # Distinct from PASSWORD_RESET_OK: a signed-in change does NOT end the
    # session, so telling the operator to sign in again would be wrong.
    "PASSWORD_CHANGED": E(
        "Password Changed", "Your password has been updated.",
        http=200, success=True, severity=SUCCESS,
        next_step="Use your new password the next time you sign in.",
        module="auth"),
    "CURRENT_PASSWORD_WRONG": E(
        "Incorrect Password", "The current password you entered isn't right.",
        http=400, severity=WARNING, retryable=True,
        next_step="Re-enter your current password, or reset it from the sign-in page.",
        module="auth", security=True),
    "PASSWORD_LOGIN_UNAVAILABLE": E(
        "Not Applicable", "This account signs in with a mobile OTP, not a password.",
        http=400, severity=INFO,
        next_step="Nothing to change — you'll always sign in with a one-time code.",
        module="auth"),
    "DELETION_REQUEST_RECEIVED": E(
        "Request Received", "Your account deletion request has been received.",
        http=200, success=True, severity=SUCCESS,
        next_step="Our team will process it within 7 days and email you to confirm.",
        module="account"),

    # ════════════════════════ SYSTEM / GENERIC ════════════════════════
    "VALIDATION_ERROR": E(
        "Check Your Details", "Some of the information entered isn't valid.",
        http=400, severity=WARNING, retryable=True,
        next_step="Correct the highlighted fields and try again.", module="system"),
    "NOT_FOUND": E(
        "Not Found", "We couldn't find what you're looking for.",
        http=404, severity=WARNING, next_step="Go back and try again.", module="system"),
    "MEDIA_UPLOADED": E(
        "Uploaded", "Your file has been uploaded.",
        http=201, success=True, severity=SUCCESS, module="media"),
    "FILE_TOO_LARGE": E(
        "File Too Large", "That file is larger than the 5 MB limit.",
        http=400, severity=WARNING, retryable=True,
        next_step="Choose a smaller image and try again.", module="media"),
    "UNSUPPORTED_MEDIA_TYPE": E(
        "Unsupported File", "Only JPG, PNG and WebP images are allowed.",
        http=400, severity=WARNING, retryable=True,
        next_step="Upload a JPG, PNG or WebP image.", module="media"),
    "CONFLICT": E(
        "Already Done", "This action has already been completed.",
        http=409, severity=INFO, module="system"),
    # A delete blocked by a PROTECT foreign key. Without this, Django's
    # ProtectedError is not a DRF exception, so it fell through the handler as a
    # bare 500 "SYSTEM_ERROR" — the operator was told the server broke when in
    # fact the record was simply still in use.
    # An inventory rule refused the movement — oversell, a pack-less movement on
    # a product sold by pack, a negative adjustment below zero. `InventoryError`
    # is a bare Exception raised throughout `inventory.services`, so every one of
    # these reached the operator as a 500 "We hit a temporary problem on our
    # end." The service's own message is already the useful sentence; this just
    # gives it a status and a code so it survives the handler.
    "INVENTORY_RULE": E(
        "Stock Move Refused", "That stock movement isn't allowed.",
        http=409, severity=WARNING, retryable=False,
        next_step="Check the quantity and the pack, then try again.",
        module="inventory"),
    "RECORD_IN_USE": E(
        "Still In Use", "This record can't be deleted because other records still depend on it.",
        http=409, severity=WARNING, retryable=False,
        next_step="Remove or reassign the dependent records first, then try again.",
        module="system"),
    # A unique-constraint violation that escaped serializer validation (a race,
    # or a constraint with no matching serializer field). Same reasoning: a 500
    # told the operator nothing, when "that code is already taken" is the truth.
    "DUPLICATE_RECORD": E(
        "Already Exists", "A record with these details already exists.",
        http=409, severity=WARNING, retryable=False,
        next_step="Use different details, or open the existing record instead.",
        module="system"),
    # ── outcomes of a destructive action ──
    # A "Delete" button does not always erase a row: anything with trading
    # history is deactivated or archived so the history stays attributable.
    # The operator has to be told which of the two happened, or they close the
    # dialog believing a store is gone while it is still sitting in the list.
    "RECORD_DELETED": E(
        "Deleted", "The record has been deleted.",
        http=200, success=True, severity=SUCCESS, module="system"),
    "RECORD_DEACTIVATED": E(
        "Deactivated", "The record has trading history, so it was deactivated instead of deleted.",
        http=200, success=True, severity=SUCCESS, module="system",
        next_step="It no longer serves customers, and its history stays intact."),
    "RECORD_ARCHIVED": E(
        "Archived", "The record has been archived.",
        http=200, success=True, severity=SUCCESS, module="system",
        next_step="It's hidden from customers but its history stays intact."),
    "RATE_LIMITED": E(
        "Slow Down", "You're doing that a bit too fast.",
        http=429, severity=WARNING, retryable=True,
        next_step="Please wait a moment and try again.", module="system"),
    "SYSTEM_ERROR": E(
        "Something Needs Attention", "We hit a temporary problem on our end.",
        http=500, severity=ERROR, retryable=True, action=RETRY,
        next_step="Please try again in a few moments.", module="system",
        security=False),
    "SERVICE_UNAVAILABLE": E(
        "Service Busy", "The service is temporarily unavailable.",
        http=503, severity=ERROR, retryable=True, action=RETRY,
        next_step="Please try again shortly.", module="system"),
    "MAINTENANCE": E(
        "Under Maintenance", "VS Mart is briefly down for maintenance.",
        http=503, severity=WARNING, next_step="We'll be back shortly.", module="system"),
    "FEATURE_DISABLED": E(
        "Not Available", "This feature isn't available right now.",
        http=403, severity=INFO, module="system"),
    "DEPENDENCY_FAILED": E(
        "Temporary Glitch", "A connected service didn't respond in time.",
        http=502, severity=ERROR, retryable=True, action=RETRY, module="system"),

    # ════════════════════════ AUTH / REGISTRATION ════════════════════════
    "AUTH_REQUIRED": E(
        "Sign In Required", "Please sign in to continue.",
        http=401, severity=WARNING, action=nav("/login"),
        next_step="Log in with your mobile number.", module="auth"),
    "PHONE_ALREADY_EXISTS": E(
        "Account Exists", "An account already exists with this mobile number.",
        http=409, severity=WARNING, action=nav("/login"),
        next_step="Log in instead, or use a different number.", module="auth"),
    "OTP_LIMIT_REACHED": E(
        "Too Many Attempts", "You've requested too many OTPs.",
        http=429, severity=WARNING, retryable=False,
        next_step="Please try again after 30 minutes.", module="auth", security=True),
    "OTP_EXPIRED": E(
        "Code Expired", "The verification code has expired.",
        http=400, severity=WARNING, retryable=True, action=RETRY,
        next_step="Request a new OTP.", module="auth"),
    "OTP_INVALID": E(
        "Incorrect Code", "The code entered doesn't match.",
        http=400, severity=WARNING, retryable=True,
        next_step="Re-enter the OTP, or request a new one.", module="auth"),
    "BLOCKED_MOBILE": E(
        "Number Restricted", "This mobile number is restricted from creating accounts.",
        http=403, severity=ERROR, action=SUPPORT,
        next_step="Contact support if you believe this is a mistake.",
        module="auth", security=True),
    "ACCOUNT_SUSPENDED": E(
        "Account Suspended", "Your account has been temporarily suspended.",
        http=403, severity=ERROR, action=SUPPORT,
        next_step="Contact support to restore access.", module="auth", security=True),
    "PROFILE_INCOMPLETE": E(
        "Complete Your Profile", "Add your name to finish setting up your account.",
        http=400, severity=INFO, action=nav("/profile/edit"),
        next_step="Enter your details to continue.", module="auth"),
    "OTP_SENT": E(
        "Code Sent", "We've sent a verification code to your mobile.",
        http=200, success=True, severity=SUCCESS, module="auth"),
    "LOGIN_SUCCESS": E(
        "Welcome Back", "You're signed in.",
        http=200, success=True, severity=SUCCESS, module="auth"),

    # ════════════════════════ SECURITY ════════════════════════
    "SESSION_EXPIRED": E(
        "Session Expired", "Your login session has expired.",
        http=401, severity=WARNING, action=LOGOUT,
        next_step="Sign in again to continue.", module="security", security=True),
    "INVALID_SESSION": E(
        "Session Invalid", "Your session is no longer valid.",
        http=401, severity=WARNING, action=LOGOUT, module="security", security=True),
    "TOKEN_REVOKED": E(
        "Signed Out", "This session was signed out.",
        http=401, severity=WARNING, action=LOGOUT, module="security", security=True),
    "MULTIPLE_DEVICE_LOGIN": E(
        "New Device Login", "Your account was logged in on another device.",
        http=401, severity=WARNING, action=REAUTH,
        next_step="Verify it's you to keep this session.", module="security", security=True),
    "DEVICE_NOT_TRUSTED": E(
        "Verify This Device", "This device needs to be verified.",
        http=403, severity=WARNING, action=REAUTH, module="security", security=True),
    "TOO_MANY_REQUESTS": E(
        "Too Many Requests", "You've exceeded the allowed request limit.",
        http=429, severity=WARNING, retryable=True,
        next_step="Please wait a bit and try again.", module="security", security=True),
    "IP_RESTRICTED": E(
        "Access Restricted", "Access from this location is restricted.",
        http=403, severity=ERROR, action=SUPPORT, module="security", security=True),
    "ACCOUNT_LOCKED": E(
        "Account Locked", "Account access has been temporarily locked.",
        http=423, severity=ERROR, action=SUPPORT,
        next_step="Try again later or contact support.", module="security", security=True),
    "INSUFFICIENT_PERMISSIONS": E(
        "Not Allowed", "You don't have permission to perform this action.",
        http=403, severity=WARNING, module="security", security=True),

    # ════════════════════════ ZONE / SERVICEABILITY ════════════════════════
    "OUTSIDE_SERVICE_AREA": E(
        "Service Unavailable", "VS Mart currently doesn't deliver to your location.",
        http=422, success=False, severity=WARNING, action=nav("/serviceability"),
        next_step="We'll notify you when we launch in your area.", module="zone"),
    # (STORE_CLOSED is defined once below, in the existing zone block.)
    "DELIVERY_CAPACITY_REACHED": E(
        "Delivery Slots Full",
        "Today's delivery capacity for your area is full. Please try again tomorrow.",
        http=422, success=False, severity=WARNING, action=nav("/cart"),
        next_step="Try again tomorrow when fresh delivery slots open.", module="zone"),
    "STORE_CHANGED": E(
        "Delivery Area Changed",
        "Your delivery address changed to a different store's area, so your cart was "
        "refreshed for what's available there.",
        http=409, success=False, severity=WARNING, action={"type": "refresh_cart"},
        next_step="Review the products available in your new area and re-add them.",
        module="zone"),
    "LOCATION_PERMISSION_REQUIRED": E(
        "Location Required", "Enable location access to check delivery availability.",
        http=400, severity=WARNING, action={"type": "navigate", "target": "/location"},
        retryable=True, next_step="Turn on location and try again.", module="zone"),
    "GPS_ACCURACY_LOW": E(
        "Can't Detect Location", "We're unable to accurately detect your location.",
        http=400, severity=WARNING, retryable=True, action=RETRY,
        next_step="Move to an open area or enter your address manually.", module="zone"),
    "ZONE_DISABLED": E(
        "Service Paused", "Deliveries are temporarily unavailable in your area.",
        http=200, success=False, severity=WARNING,
        next_step="Please check back soon.", module="zone"),
    "NO_STORE_ASSIGNED": E(
        "No Store Nearby", "No active store serves this location yet.",
        http=200, success=False, severity=WARNING, action=nav("/serviceability"),
        module="zone"),
    "STORE_CLOSED": E(
        "Store Closed", "The nearest store is currently closed.",
        http=409, severity=WARNING,
        next_step="Try again during store hours.", module="zone"),
    "SERVICEABLE": E(
        "We Deliver Here", "Great news — we deliver to your location.",
        http=200, success=True, severity=SUCCESS, module="zone"),

    # ════════════════════════ CATALOG / SEARCH ════════════════════════
    "PRODUCT_SUGGESTIONS": E(
        "Suggestions", "",
        http=200, success=True, severity=SUCCESS, module="catalog"),

    # ════════════════════════ KYC / VERIFICATION ════════════════════════
    "KYC_NOT_STARTED": E(
        "Verification Required", "Complete verification before applying for credit.",
        http=403, severity=WARNING, action=nav("/verification"),
        next_step="Complete KYC to unlock credit services.", module="kyc"),
    "KYC_REQUIRED": E(
        "Verification Required", "Complete your identity verification before applying for credit.",
        http=403, severity=WARNING, action=nav("/verification"),
        next_step="Complete KYC to unlock credit services.", module="kyc"),
    "VERIFICATION_PENDING": E(
        "Under Review", "Your verification is currently under review.",
        http=200, success=False, severity=INFO,
        next_step="We'll notify you once it's approved (usually 1–2 days).", module="kyc"),
    "VERIFICATION_REJECTED": E(
        "Verification Not Approved", "Verification couldn't be approved.",
        http=200, success=False, severity=WARNING, action=RETRY_VERIFICATION,
        next_step="Review the remarks and resubmit your documents.", module="kyc"),
    "DOCUMENT_BLURRY": E(
        "Document Unclear", "The uploaded document is unclear.",
        http=400, severity=WARNING, retryable=True, action=RETRY_VERIFICATION,
        next_step="Re-upload a clear, well-lit photo.", module="kyc"),
    "FACE_MISMATCH": E(
        "Selfie Mismatch", "Your selfie doesn't match the submitted identity documents.",
        http=400, severity=WARNING, action=RETRY_VERIFICATION,
        next_step="Retake your selfie in good lighting.", module="kyc"),
    "PAN_INVALID": E(
        "PAN Not Verified", "The PAN entered couldn't be verified.",
        http=400, severity=WARNING, retryable=True,
        next_step="Check the PAN number and try again.", module="kyc"),
    "PAN_NAME_MISMATCH": E(
        "Details Don't Match", "PAN details do not match your Aadhaar records.",
        http=400, severity=WARNING, action=RETRY_VERIFICATION,
        next_step="Re-check your details and resubmit.", module="kyc", risk=True),
    "PAN_NUMBER_MISMATCH": E(
        "PAN Doesn't Match", "The PAN you entered doesn't match the PAN on your credit record.",
        http=400, severity=WARNING, action=RETRY_VERIFICATION,
        next_step="Check the PAN number and resubmit.", module="kyc", risk=True),
    "AADHAAR_INVALID": E(
        "Aadhaar Not Validated", "The Aadhaar details couldn't be validated.",
        http=400, severity=WARNING, retryable=True,
        next_step="Verify the Aadhaar details and try again.", module="kyc"),
    "AADHAAR_ALREADY_USED": E(
        "Already Linked", "This Aadhaar is already linked to another account.",
        http=409, severity=ERROR, action=SUPPORT,
        next_step="Contact support if this isn't expected.", module="kyc",
        security=True, risk=True),
    "DUPLICATE_KYC": E(
        "Already Verified Elsewhere", "Identity verification already exists on another account.",
        http=409, severity=ERROR, action=SUPPORT, module="kyc", security=True, risk=True),
    "KYC_AGE_RESTRICTED": E(
        "Not Eligible For Credit", "You must be at least 18 years old to apply for credit.",
        http=403, severity=WARNING, retryable=False,
        next_step="Continue shopping using prepaid payment methods.", module="kyc"),
    "GPS_VERIFICATION_FAILED": E(
        "Location Check Failed", "Location verification was unsuccessful.",
        http=400, severity=WARNING, retryable=True, action=RETRY,
        next_step="Ensure GPS is on and try again.", module="kyc"),
    "HOUSE_VERIFICATION_PENDING": E(
        "Field Verification Pending", "Field verification of your address is still pending.",
        http=200, success=False, severity=INFO,
        next_step="Our agent will visit soon — no action needed.", module="kyc"),
    "KYC_SUBMITTED": E(
        "Submitted For Review", "Your verification has been submitted.",
        http=200, success=True, severity=SUCCESS,
        next_step="We'll review it within 1–2 days.", module="kyc"),
    "KYC_VERIFIED": E(
        "Verified", "Your identity has been verified.",
        http=200, success=True, severity=SUCCESS, module="kyc"),
    # ── API verification (Setu): outcomes of a gov-source check ──
    "PAN_VERIFIED": E(
        "PAN Verified", "Your PAN was verified successfully.",
        http=200, success=True, severity=SUCCESS, module="kyc"),
    "AADHAAR_VERIFIED": E(
        "Aadhaar Verified", "Your Aadhaar was verified successfully.",
        http=200, success=True, severity=SUCCESS, module="kyc"),
    "BANK_VERIFIED": E(
        "Bank Account Verified", "Your bank account was verified successfully.",
        http=200, success=True, severity=SUCCESS, module="kyc"),
    "DIGILOCKER_CONSENT_REQUIRED": E(
        "Authorise on DigiLocker", "Continue on DigiLocker to share your Aadhaar.",
        http=200, success=True, severity=INFO,
        next_step="Approve the request in DigiLocker, then return to the app.", module="kyc"),
    "DIGILOCKER_PENDING": E(
        "Awaiting DigiLocker", "We haven't received your DigiLocker consent yet.",
        http=200, success=False, severity=INFO, retryable=True,
        next_step="Complete the consent in DigiLocker and try again.", module="kyc"),
    "AADHAAR_OTP_SENT": E(
        "OTP Sent", "An OTP has been sent to your Aadhaar-linked mobile number.",
        http=200, success=True, severity=SUCCESS,
        next_step="Enter the OTP to verify your Aadhaar.", module="kyc"),
    "AADHAAR_OTP_INVALID": E(
        "Incorrect OTP", "The OTP entered is incorrect or has expired.",
        http=400, severity=WARNING, retryable=True,
        next_step="Re-enter the OTP, or request a new one.", module="kyc"),
    "BANK_VERIFICATION_FAILED": E(
        "Bank Account Not Verified", "We couldn't verify the bank account details.",
        http=400, severity=WARNING, retryable=True, action=RETRY,
        next_step="Check the account number and IFSC, then try again.", module="kyc"),
    "CONSENT_REQUIRED": E(
        "Consent Needed", "We need your consent to verify these details.",
        http=400, severity=WARNING,
        next_step="Tick the consent box to continue.", module="kyc"),
    "KYC_PROVIDER_ERROR": E(
        "Verification Unavailable", "The verification service is temporarily unavailable.",
        http=503, severity=WARNING, retryable=True, action=RETRY,
        next_step="Please try again in a few minutes.", module="kyc"),

    # ════════════════════════ CREDIT ════════════════════════
    "CREDIT_DISABLED": E(
        "Credit Unavailable", "Credit purchasing is currently unavailable on your account.",
        http=403, severity=WARNING, action=nav("/credit"),
        next_step="Complete KYC or contact support to enable credit.", module="credit"),
    "AGE_NOT_ELIGIBLE": E(
        "Credit Not Available", "You must be at least 18 years old to apply for credit.",
        http=403, severity=WARNING, retryable=False,
        next_step="Continue shopping using prepaid payment methods.", module="credit"),
    "LIMIT_EXCEEDED": E(
        "Credit Limit Reached", "Your outstanding balance exceeds your available credit.",
        http=409, severity=WARNING, action=nav("/credit/repay"),
        next_step="Repay some dues or reduce your cart to continue.", module="credit", risk=True),
    "OVERDUE_PAYMENT": E(
        "Payment Required", "Clear your overdue dues before placing a new credit order.",
        http=402, severity=WARNING, action=nav("/credit/repay"),
        next_step="Pay your outstanding amount to unlock credit again.",
        module="credit", risk=True),
    "CREDIT_OVERPAYMENT": E(
        "Amount Too High", "You're trying to pay more than you owe.",
        http=409, severity=WARNING,
        next_step="Enter an amount up to your current outstanding balance.",
        module="credit"),
    "CREDIT_NO_DUES": E(
        "Nothing to Repay", "Your credit balance is already clear.",
        http=409, severity=INFO, action=nav("/credit"),
        next_step="There's no outstanding amount on your account.", module="credit"),
    "HIGH_RISK_CUSTOMER": E(
        "Account Under Review", "Your account is currently classified as high risk.",
        http=403, severity=ERROR, action=SUPPORT,
        next_step="Contact support to review your account.", module="credit",
        risk=True, security=True),
    "CREDIT_FROZEN": E(
        "Credit Temporarily Disabled", "Your credit usage has been temporarily frozen.",
        http=403, severity=ERROR, action=SUPPORT,
        next_step="Contact customer support for assistance.", module="credit", risk=True),
    "CREDIT_SUSPENDED": E(
        "Credit Suspended", "Your credit privileges have been suspended.",
        http=403, severity=ERROR, action=SUPPORT,
        next_step="Contact support to understand next steps.", module="credit", risk=True),
    "CREDIT_UNDER_REVIEW": E(
        "Credit Under Review", "Your account is under credit review.",
        http=403, severity=INFO,
        next_step="We'll notify you once the review is complete.", module="credit"),
    "CREDIT_NOT_ELIGIBLE": E(
        "Not Eligible Yet", "Your account isn't eligible for credit yet.",
        http=403, severity=WARNING, action=nav("/verification"),
        next_step="Complete KYC and build your VS Score to qualify.", module="credit"),
    # ── Credit application (apply -> review -> decision) ──
    "CREDIT_APPLICATION_SUBMITTED": E(
        "Application Submitted", "Your VS Credit application is in for review.",
        http=201, success=True, severity=INFO,
        next_step="We'll notify you once a decision is made, usually within a day.",
        module="credit"),
    "CREDIT_APPLICATION_APPROVED": E(
        "Credit Approved", "The credit application was approved.",
        http=200, success=True, severity=INFO, module="credit"),
    "CREDIT_APPLICATION_REJECTED": E(
        "Application Not Approved", "The credit application was rejected.",
        http=200, success=True, severity=INFO, module="credit"),
    "CREDIT_APPLICATION_IN_REVIEW": E(
        "Already Under Review", "Your credit application is already under review.",
        http=409, severity=INFO, action=nav("/credit"),
        next_step="We'll notify you once a decision is made.", module="credit"),
    "CREDIT_ALREADY_ACTIVE": E(
        "Credit Already Active", "You already have an active VS Credit line.",
        http=409, severity=INFO, action=nav("/credit"),
        next_step="Open the Credit tab to see your limit.", module="credit"),
    "INVALID_CREDIT_TRANSITION": E(
        "Action Not Allowed", "That credit application can't move to this state.",
        http=409, severity=WARNING, module="credit"),
    "INVALID_CREDIT_LIMIT": E(
        "Invalid Limit", "The credit limit provided isn't valid.",
        http=400, severity=WARNING, module="credit"),
    "RECEIPT_NOT_READY": E(
        "Receipt Not Ready", "A receipt is available once the payment completes.",
        http=409, severity=INFO, module="payments"),

    # ── General ledger ──
    "GL_POSTED": E(
        "Entry Posted", "The journal entry has been posted.",
        http=201, success=True, severity=SUCCESS, module="accounting"),
    "GL_REVERSED": E(
        "Entry Reversed", "A reversing entry has been posted.",
        http=200, success=True, severity=SUCCESS, module="accounting"),
    "GL_UNBALANCED": E(
        "Entry Doesn't Balance", "Debits and credits must be equal.",
        http=400, severity=WARNING,
        next_step="Adjust the lines so both sides match.", module="accounting"),
    "GL_ACCOUNT_UNKNOWN": E(
        "Unknown Account", "That ledger account doesn't exist or is archived.",
        http=400, severity=WARNING, module="accounting"),
    "GL_INVALID_TRANSITION": E(
        "Action Not Allowed", "That journal entry can't be changed this way.",
        http=409, severity=WARNING, module="accounting"),
    "GL_ALREADY_REVERSED": E(
        "Already Reversed", "This entry has already been reversed.",
        http=409, severity=INFO, module="accounting"),

    # ── Cash book ──
    "CASH_DEPOSIT_RECORDED": E(
        "Deposit Recorded", "Your cash hand-over has been recorded.",
        http=201, success=True, severity=SUCCESS,
        next_step="Finance will verify the amount and confirm.", module="payments"),
    "INVALID_DEPOSIT_TRANSITION": E(
        "Already Reviewed", "This deposit has already been reviewed.",
        http=409, severity=WARNING, module="payments"),
    "DEPOSIT_COLLECTION_CONFLICT": E(
        "Already Deposited", "Some of those collections are already banked.",
        http=409, severity=WARNING,
        next_step="Refresh and try again.", module="payments"),
    "CASH_HANDOVER_STORE_MISSING": E(
        "No Store Linked",
        "You aren't linked to a store, so an online hand-over can't be routed.",
        http=409, severity=WARNING,
        next_step="Ask your admin to link you to a store, or hand the cash over "
                  "in person.", module="payments"),
    "CASH_ONLINE_INITIATED": E(
        "Pay to Complete",
        "Your online hand-over is ready. Pay the link to send the money to your "
        "store.",
        http=201, success=True, severity=INFO,
        next_step="Complete the payment, then tap 'I've paid'.", module="payments"),
    "CASH_ONLINE_CONFIRMED": E(
        "Hand-over Complete",
        "The store has received your online hand-over.",
        http=200, success=True, severity=SUCCESS, module="payments"),
    "CASH_ONLINE_PENDING": E(
        "Payment Not Received Yet",
        "We haven't seen this payment land yet.",
        http=200, success=True, severity=INFO,
        next_step="Finish paying the link, then check again.", module="payments"),
    "CASH_ONLINE_FAILED": E(
        "Hand-over Cancelled",
        "The online payment was cancelled or expired, so nothing was handed over.",
        http=409, severity=WARNING,
        next_step="The cash is still shown against you — try again.",
        module="payments"),

    # ── Accounts payable ──
    "INVALID_AP_TRANSITION": E(
        "Action Not Allowed", "That supplier invoice can't move to this state.",
        http=409, severity=WARNING, module="procurement"),
    "AP_OVERPAYMENT": E(
        "Amount Too High", "That payment exceeds the balance owed on this invoice.",
        http=400, severity=WARNING, module="procurement"),
    "LIMIT_INCREASE_PENDING": E(
        "Review In Progress", "Your credit limit review request is still being processed.",
        http=200, success=False, severity=INFO,
        next_step="We'll update you once it's reviewed.", module="credit"),
    "LIMIT_INCREASE_APPROVED": E(
        "Limit Increased", "Your credit limit has been increased.",
        http=200, success=True, severity=SUCCESS, module="credit"),
    "LIMIT_INCREASE_REJECTED": E(
        "Request Not Approved", "Your credit limit review request wasn't approved.",
        http=200, success=False, severity=WARNING,
        next_step="Keep paying on time to improve eligibility.", module="credit"),
    "REPAYMENT_SUCCESS": E(
        "Payment Received", "Your repayment was successful.",
        http=200, success=True, severity=SUCCESS,
        next_step="Your available credit has been restored.", module="credit"),
    # ── CIBIL / credit-bureau score ──
    "CIBIL_FETCHED": E(
        "Credit Score Ready", "Your CIBIL credit score has been fetched.",
        http=200, success=True, severity=SUCCESS, module="credit"),
    "CIBIL_CONSENT_REQUIRED": E(
        "Consent Needed", "We need your consent to fetch your CIBIL credit score.",
        http=400, severity=WARNING,
        next_step="Tick the consent box to check your score.", module="credit"),
    "CIBIL_NO_RECORD": E(
        "No Credit Record", "No CIBIL record was found for this mobile number.",
        http=200, success=False, severity=INFO, retryable=True,
        next_step="It may have been queried recently, or there's no bureau history yet.",
        module="credit"),
    "CIBIL_PROVIDER_ERROR": E(
        "Score Check Unavailable", "The credit-score service is temporarily unavailable.",
        http=503, severity=WARNING, retryable=True, action=RETRY,
        next_step="Please try again in a few minutes.", module="credit"),
    "CIBIL_CHECKED": E(
        "Score Verified", "Your identity and CIBIL score check out.",
        http=200, severity=SUCCESS,
        next_step="Upload your documents to finish.", module="credit"),
    "CIBIL_SCORE_LOW": E(
        "Score Too Low", "Your CIBIL score doesn't meet the minimum for VS Credit yet.",
        http=200, success=False, severity=INFO,
        next_step="Build your score and try again later.", module="credit"),
    "CIBIL_CHECK_REQUIRED": E(
        "Check Your Score First", "Complete the CIBIL check before uploading documents.",
        http=409, severity=WARNING,
        next_step="Run the CIBIL check, then continue.", module="credit"),

    # ════════════════════════ ORDERING ════════════════════════
    "CART_EMPTY": E(
        "Cart Is Empty", "Add items before placing an order.",
        http=400, severity=INFO, action=nav("/home"),
        next_step="Browse products and add them to your cart.", module="orders"),
    "MIN_ORDER_NOT_MET": E(
        "Add A Little More", "Your cart hasn't reached the minimum order value.",
        http=400, severity=WARNING, action=nav("/cart"),
        next_step="Add more items to meet the minimum order.", module="orders"),
    "OUT_OF_STOCK": E(
        "Item Unavailable", "One or more items in your cart are currently out of stock.",
        http=409, severity=WARNING, action=nav("/cart"),
        next_step="Remove the unavailable items to continue.", module="orders"),
    "PRODUCT_UNAVAILABLE": E(
        "Not Available At Your Store",
        "One or more items in your cart aren't carried by the store that serves your "
        "area. Remove them to continue.",
        http=409, severity=WARNING, action=nav("/cart"),
        next_step="Remove the items not available in your area to continue.",
        module="orders"),
    "INSUFFICIENT_QUANTITY": E(
        "Not Enough Stock", "The requested quantity exceeds what's available.",
        http=409, severity=WARNING, action=nav("/cart"),
        next_step="Reduce the quantity and try again.", module="orders"),
    "STOCK_UPDATED": E(
        "Cart Updated", "Product quantities changed while you were checking out.",
        http=409, severity=WARNING, action=nav("/cart"),
        next_step="Review your updated cart before placing the order.", module="orders"),
    "STORE_INVENTORY_CHANGED": E(
        "Availability Changed", "Some items in your cart have changed in availability.",
        http=409, severity=WARNING, action=nav("/cart"),
        next_step="Review your cart and continue.", module="orders"),
    "PRICE_UPDATED": E(
        "Prices Updated", "Prices changed since the items were added to your cart.",
        http=409, severity=INFO, action=nav("/cart"),
        next_step="Review the new total before continuing.", module="orders"),
    "PRODUCT_DISABLED": E(
        "Product Unavailable", "This product is no longer available.",
        http=410, severity=WARNING, action=nav("/cart"),
        next_step="Remove it from your cart to continue.", module="orders"),
    "ORDER_ALREADY_PLACED": E(
        "Already Placed", "This order has already been processed.",
        http=409, severity=INFO, action=nav("/orders"), module="orders"),
    "DUPLICATE_ORDER": E(
        "Looks Familiar", "A similar order was placed just moments ago.",
        http=409, severity=WARNING, action=nav("/orders"),
        next_step="Check your orders before trying again.", module="orders"),
    "ORDER_NOT_CANCELLABLE": E(
        "Can't Cancel", "This order can no longer be cancelled.",
        http=409, severity=WARNING,
        next_step="Contact support if you need help.", module="orders"),
    "ORDER_STATUS_INVALID": E(
        "Invalid Status Change", "This order can't move to that status from where it is.",
        http=409, severity=ERROR,
        next_step="Refresh the order — someone may have already updated it.",
        module="orders"),
    "ORDER_ACCEPTED": E(
        "Order Placed", "Your order has been successfully placed.",
        http=201, success=True, severity=SUCCESS,
        next_step="Track it live from My Orders.", module="orders"),
    "ORDER_CANCELLED": E(
        "Order Cancelled", "The order has been cancelled.",
        http=200, success=True, severity=INFO, module="orders"),
    "ORDER_CANCELLED_STORE": E(
        "Order Cancelled", "The store cancelled this order due to inventory issues.",
        http=200, success=True, severity=WARNING,
        next_step="Any amount paid will be refunded automatically.", module="orders"),
    "ORDER_DELIVERED": E(
        "Delivered", "Your order has been successfully delivered.",
        http=200, success=True, severity=SUCCESS, module="orders"),
    "REORDER_SUCCESS": E(
        "Added To Cart", "Items from your previous order were added to the cart.",
        http=200, success=True, severity=SUCCESS, action=nav("/cart"), module="orders"),

    # ════════════════════════ PAYMENTS / FINANCE ════════════════════════
    "COD_NOT_AVAILABLE": E(
        "Cash On Delivery Unavailable", "Cash on Delivery isn't available for this order.",
        http=400, severity=WARNING,
        next_step="Choose UPI, card, or VS Credit instead.", module="payments"),
    "PAYMENT_FAILED": E(
        "Payment Failed", "The transaction couldn't be completed.",
        http=402, severity=ERROR, retryable=True, action=RETRY,
        next_step="Try again or use a different payment method.", module="payments"),
    "PAYMENT_PENDING": E(
        "Awaiting Confirmation", "We're waiting for your bank to confirm the payment.",
        http=202, success=False, severity=INFO,
        next_step="This usually takes a moment — don't pay again.", module="payments"),
    "PAYMENT_CANCELLED": E(
        "Payment Cancelled", "You cancelled the payment.",
        http=200, success=False, severity=INFO, retryable=True, action=RETRY,
        next_step="Retry whenever you're ready.", module="payments"),
    "PAYMENT_GATEWAY_ERROR": E(
        "Gateway Unavailable", "The payment gateway didn't respond.",
        http=502, severity=ERROR, retryable=True, action=RETRY, module="payments"),
    "PAYMENT_SUCCESS": E(
        "Payment Successful", "Your payment was successful.",
        http=200, success=True, severity=SUCCESS, module="payments"),
    "PAYMENT_ALREADY_COMPLETED": E(
        "Already Paid", "This order has already been paid for.",
        http=409, severity=INFO,
        next_step="Open the order to see its status — don't pay again.",
        module="payments"),
    "PAYMENT_AMOUNT_MISMATCH": E(
        "Amount Mismatch", "The amount settled doesn't match what was due.",
        http=409, severity=CRITICAL,
        next_step="Contact support with your payment reference — don't retry.",
        module="payments"),
    "PAYMENT_RECONCILIATION_REQUIRED": E(
        "Needs Reconciliation",
        "We couldn't confirm this payment with the gateway and it needs a manual check.",
        http=409, severity=CRITICAL,
        next_step="Check the gateway dashboard, then resolve it as captured or failed.",
        module="payments"),
    "PAYMENT_NOT_UNDER_REVIEW": E(
        "Not Awaiting Review", "This payment isn't awaiting manual reconciliation.",
        http=409, severity=WARNING,
        next_step="Refresh the list — it may already have been resolved.",
        module="payments"),
    "PAYMENT_RESOLVER_REQUIRED": E(
        "Who Decided?", "A manual reconciliation must record who made the decision.",
        http=400, severity=WARNING,
        next_step="Sign in again and retry.",
        module="payments"),
    "PAYMENT_ATTESTATION_REQUIRED": E(
        "Verification Required",
        "Confirm you have verified this capture in the payment provider's dashboard.",
        http=400, severity=WARNING,
        next_step="Open the provider dashboard, find the capture, then tick the box.",
        module="payments"),
    "PAYMENT_CAPTURED_AMOUNT_REQUIRED": E(
        "Captured Amount Required",
        "Enter the amount the payment provider actually captured.",
        http=400, severity=WARNING,
        next_step="Copy the captured amount from the provider dashboard.",
        module="payments"),
    "PAYMENT_RESOLUTION_INVALID": E(
        "Invalid Resolution", "Resolve the payment as 'captured' or 'failed'.",
        http=400, severity=WARNING,
        next_step="Pick what the gateway actually shows — never guess.",
        module="payments"),
    "REFUND_INITIATED": E(
        "Refund Started", "Your refund has been initiated.",
        http=200, success=True, severity=SUCCESS,
        next_step="It will reflect in 3–5 business days.", module="finance"),
    "REFUND_COMPLETED": E(
        "Refund Completed", "Your refund has been completed.",
        http=200, success=True, severity=SUCCESS, module="finance"),
    "REFUND_REJECTED": E(
        "Refund Not Approved", "The refund request wasn't approved.",
        http=200, success=False, severity=WARNING, action=SUPPORT,
        next_step="Contact support to know more.", module="finance"),
    "LEDGER_LOCKED": E(
        "Period Closed", "This accounting period has already been closed.",
        http=409, severity=ERROR, module="finance"),
    "JOURNAL_POSTED": E(
        "Entry Posted", "The financial entry has been posted successfully.",
        http=201, success=True, severity=SUCCESS, module="finance"),
    "NO_DUES_FOUND": E(
        "Nothing Due", "You have no outstanding payments.",
        http=200, success=False, severity=INFO,
        next_step="Nothing to pay right now.", module="finance"),

    # ════════════════════════ DELIVERY ════════════════════════
    "AGENT_UNAVAILABLE": E(
        "Assignment Delayed", "Delivery assignment is delayed due to agent availability.",
        http=200, success=False, severity=WARNING,
        next_step="We'll assign an agent shortly.", module="delivery"),
    "AGENT_NOT_ASSIGNED": E(
        "No Agent Yet", "No delivery agent has been assigned to this order.",
        http=200, success=False, severity=INFO, module="delivery"),
    "AGENT_ASSIGNED": E(
        "Agent Assigned", "A delivery agent has been assigned.",
        http=200, success=True, severity=SUCCESS, module="delivery"),
    "PICKUP_FAILED": E(
        "Pickup Failed", "The pickup couldn't be completed.",
        http=409, severity=WARNING, retryable=True, action=RETRY, module="delivery"),
    "CUSTOMER_UNREACHABLE": E(
        "Customer Unreachable", "The customer couldn't be contacted.",
        http=200, success=False, severity=WARNING,
        next_step="Try the next attempt or reschedule.", module="delivery"),
    "ADDRESS_NOT_FOUND": E(
        "Address Not Found", "The delivery location couldn't be located.",
        http=404, severity=WARNING, action=nav("/addresses"),
        next_step="Verify or update the delivery address.", module="delivery"),
    "INVALID_DELIVERY_OTP": E(
        "Wrong OTP", "The delivery OTP entered is incorrect.",
        http=400, severity=WARNING, retryable=True,
        next_step="Ask the customer for the correct OTP.", module="delivery"),
    # `generated_at` was recorded on every delivery OTP and never once read, so a
    # code stayed valid indefinitely: a re-attempted delivery the next day still
    # accepted yesterday's code, and the handover credential sat live in the
    # customer's inbox forever.
    "DELIVERY_OTP_EXPIRED": E(
        "Code Expired", "That delivery code has expired.",
        http=400, severity=WARNING, retryable=True, action=RETRY,
        next_step="Confirm your arrival again to send the customer a fresh code.",
        module="delivery"),
    "DELIVERY_FAILED": E(
        "Delivery Failed", "The delivery attempt was unsuccessful.",
        http=200, success=False, severity=WARNING,
        next_step="Reschedule or return the order.", module="delivery"),
    "DELIVERY_RESCHEDULED": E(
        "Rescheduled", "The delivery has been rescheduled.",
        http=200, success=True, severity=INFO, module="delivery"),
    "DELIVERY_COMPLETED": E(
        "Delivered", "The order was delivered successfully.",
        http=200, success=True, severity=SUCCESS, module="delivery"),
    "DELIVERY_ASSIGNED": E(
        "Delivery Assigned", "An agent has been assigned to this order.",
        http=200, success=True, severity=SUCCESS, module="delivery"),
    "PICKED_UP": E(
        "Picked Up", "The order has been picked up from the store.",
        http=200, success=True, severity=SUCCESS, module="delivery"),
    "OUT_FOR_DELIVERY": E(
        "Out For Delivery", "The order is on its way.",
        http=200, success=True, severity=SUCCESS, module="delivery"),
    "REACHED_LOCATION": E(
        "Reached", "The agent has reached the delivery location.",
        http=200, success=True, severity=SUCCESS, module="delivery"),
    "DELIVERY_OTP_SENT": E(
        "OTP Sent", "A delivery code has been sent to the customer.",
        http=200, success=True, severity=SUCCESS, module="delivery"),
    "DELIVERY_OTP_VERIFIED": E(
        "OTP Verified", "The delivery code was verified.",
        http=200, success=True, severity=SUCCESS, module="delivery"),
    "DELIVERY_LOCATION_MISMATCH": E(
        "Not At Location", "You must be within 50 metres of the delivery address to complete it.",
        http=409, severity=WARNING, retryable=True,
        next_step="Move closer to the delivery point and try again.", module="delivery"),
    "MANUAL_VERIFICATION_REQUIRED": E(
        "Manual Verification Needed", "Too many incorrect OTP attempts — store approval is required.",
        http=423, severity=ERROR, action=SUPPORT,
        next_step="Contact the store to verify this delivery manually.",
        module="delivery", security=True),
    "DELIVERY_TASK_REQUIRED": E(
        "No Active Delivery", "This delivery isn't assigned to you as an active task.",
        http=409, severity=ERROR,
        next_step="Refresh your task list — it may have been reassigned.",
        module="delivery"),
    "DELIVERY_OTP_REQUIRED": E(
        "Verify OTP First", "Verify the customer's delivery OTP before completing.",
        http=409, severity=WARNING,
        next_step="Ask the customer for the 6-digit code and verify it.", module="delivery"),
    "DELIVERY_PHOTO_REQUIRED": E(
        "Photo Required", "Capture proof-of-delivery before completing.",
        http=409, severity=WARNING,
        next_step="Take a photo of the delivered package at the doorstep.", module="delivery"),
    "INVALID_DELIVERY_TRANSITION": E(
        "Action Not Allowed", "That delivery step can't be done from the current status.",
        http=409, severity=WARNING,
        next_step="Refresh and follow the delivery steps in order.", module="delivery"),
    "FAILED_CUSTOMER_UNREACHABLE": E(
        "Customer Unreachable", "The customer could not be contacted at delivery.",
        http=200, success=False, severity=WARNING,
        next_step="Reschedule or return the order to store.", module="delivery"),
    "FAILED_ADDRESS_NOT_FOUND": E(
        "Address Not Found", "The delivery address could not be located.",
        http=200, success=False, severity=WARNING,
        next_step="Reschedule after confirming the address.", module="delivery"),
    "FAILED_CUSTOMER_REJECTED": E(
        "Customer Refused", "The customer refused the delivery.",
        http=200, success=False, severity=WARNING,
        next_step="Return the order to store.", module="delivery"),
    "FAILED_SECURITY_CONCERN": E(
        "Safety Issue", "The delivery was stopped due to a safety concern.",
        http=200, success=False, severity=ERROR, action=SUPPORT,
        next_step="Report to the store immediately.", module="delivery", security=True),
    "REATTEMPT_SCHEDULED": E(
        "Re-attempt Scheduled", "A new delivery attempt has been scheduled.",
        http=200, success=True, severity=INFO, module="delivery"),
    "RETURN_TO_STORE": E(
        "Returned To Store", "The undelivered order has been returned to the store.",
        http=200, success=True, severity=INFO, module="delivery"),

    # ════════════════════════ COLLECTIONS ════════════════════════
    "COLLECTION_CREATED": E(
        "Collection Created", "The collection task has been created.",
        http=201, success=True, severity=SUCCESS, module="collections"),
    "COLLECTION_ASSIGNED": E(
        "Already Assigned", "This recovery task is already assigned to another agent.",
        http=409, severity=WARNING, module="collections"),
    "COLLECTION_COMPLETED": E(
        "Payment Collected", "The payment was collected successfully.",
        http=200, success=True, severity=SUCCESS, module="collections"),
    "COLLECTION_FAILED": E(
        "Collection Failed", "The collection attempt was unsuccessful.",
        http=200, success=False, severity=WARNING, module="collections"),
    "CUSTOMER_NOT_AVAILABLE": E(
        "Customer Unavailable", "The customer was unavailable for collection.",
        http=200, success=False, severity=WARNING,
        next_step="Reschedule the visit.", module="collections"),
    "PAYMENT_DISPUTE": E(
        "Dispute Raised", "The customer has raised a payment dispute.",
        http=200, success=False, severity=WARNING, action=SUPPORT,
        next_step="Escalate to the collections supervisor.", module="collections", risk=True),
    "PARTIAL_PAYMENT": E(
        "Partial Payment", "Only part of the amount was collected.",
        http=200, success=True, severity=INFO,
        next_step="The remaining balance stays due.", module="collections"),
    "RECOVERY_CLOSED": E(
        "Fully Recovered", "The outstanding amount has been fully recovered.",
        http=200, success=True, severity=SUCCESS, module="collections"),
    "COLLECTION_ACCEPTED": E(
        "Collection Accepted", "You've accepted this collection task.",
        http=200, success=True, severity=SUCCESS, module="collections"),
    "COLLECTION_EN_ROUTE": E(
        "On The Way", "You're on the way to the customer.",
        http=200, success=True, severity=SUCCESS, module="collections"),
    "COLLECTION_REACHED": E(
        "Reached Customer", "You've reached the customer location.",
        http=200, success=True, severity=SUCCESS, module="collections"),
    "COLLECTION_OTP_SENT": E(
        "OTP Sent", "A collection code has been sent to the customer.",
        http=200, success=True, severity=SUCCESS, module="collections"),
    "COLLECTION_OTP_VERIFIED": E(
        "OTP Verified", "The collection code was verified.",
        http=200, success=True, severity=SUCCESS, module="collections"),
    "INVALID_COLLECTION_OTP": E(
        "Wrong OTP", "The collection OTP entered is incorrect.",
        http=400, severity=WARNING, retryable=True,
        next_step="Ask the customer for the correct 6-digit code.", module="collections"),
    "COLLECTION_OTP_REQUIRED": E(
        "Verify OTP First", "Verify the customer's OTP before recording cash.",
        http=409, severity=WARNING,
        next_step="Send and verify the collection OTP.", module="collections"),
    "COLLECTION_OTP_EXPIRED": E(
        "Code Expired", "That confirmation code has expired.",
        http=400, severity=WARNING, retryable=True, action=RETRY,
        next_step="Request a new code for the customer to confirm.",
        module="collections"),
    "COLLECTION_OTP_LOCKED": E(
        "Verification Locked", "Too many incorrect OTP attempts — supervisor approval needed.",
        http=423, severity=ERROR, action=SUPPORT,
        next_step="Contact the collections supervisor.", module="collections", security=True, risk=True),
    # A locked collection could never be unlocked: `collect()` requires
    # `otp_verified`, and unlike delivery there was no supervisor override at all
    # — an agent standing there holding the customer's cash had no way to finish.
    "COLLECTION_MANUALLY_VERIFIED": E(
        "Manually Verified", "A supervisor has verified this collection.",
        http=200, success=True, severity=SUCCESS, module="collections",
        next_step="Record the cash collected.", security=True),
    # The collections twin of DELIVERY_TASK_REQUIRED. A push alert is a
    # snapshot; by the time the agent taps, auto-assignment may already have
    # moved the collection to someone else. Distinct from a transition error so
    # the app can dismiss the alert instead of inviting a pointless retry.
    "COLLECTION_TASK_REQUIRED": E(
        "No Longer Yours", "This collection isn't assigned to you as an active task.",
        http=409, severity=WARNING,
        next_step="Refresh your task list — it may have been reassigned.",
        module="collections"),
    "INVALID_COLLECTION_TRANSITION": E(
        "Action Not Allowed", "That collection step can't be done from the current status.",
        http=409, severity=WARNING,
        next_step="Refresh and follow the collection steps in order.", module="collections"),
    "COLLECTION_AMOUNT_INVALID": E(
        "Invalid Amount", "The amount must be greater than zero and within the due balance.",
        http=400, severity=WARNING,
        next_step="Enter an amount up to the outstanding due.", module="collections"),
    "COLLECTION_CANCELLED": E(
        "Collection Cancelled", "This collection task was cancelled.",
        http=200, success=True, severity=INFO, module="collections"),

    # ════════════════════════ INVENTORY ════════════════════════
    "LOW_STOCK_ALERT": E(
        "Low Stock", "Inventory levels are running low.",
        http=200, success=True, severity=WARNING,
        next_step="Plan a replenishment soon.", module="inventory"),
    "CRITICAL_STOCK": E(
        "Critical Stock", "Immediate replenishment is recommended.",
        http=200, success=True, severity=ERROR,
        next_step="Raise a purchase order now.", module="inventory"),
    "EXPIRY_WARNING": E(
        "Expiry Approaching", "This product's expiry is approaching.",
        http=200, success=True, severity=WARNING, module="inventory"),
    "NEAR_EXPIRY_PRODUCT": E(
        "Near Expiry", "This product is approaching its expiry date.",
        http=200, success=True, severity=WARNING,
        next_step="Prioritise it for sale or markdown.", module="inventory"),
    "PRODUCT_EXPIRED": E(
        "Expired Product", "Expired products cannot be sold.",
        http=409, severity=ERROR,
        next_step="Move it to damaged/expired stock.", module="inventory"),
    "BATCH_EXPIRED": E(
        "Batch Expired", "This batch can't be added because it's already expired.",
        http=409, severity=ERROR, module="inventory"),
    "DUPLICATE_BATCH": E(
        "Batch Exists", "This batch already exists.",
        http=409, severity=WARNING, module="inventory"),
    "NEGATIVE_STOCK_PREVENTION": E(
        "Stock Can't Go Negative", "Stock cannot become negative.",
        http=409, severity=ERROR,
        next_step="Check the quantity and try again.", module="inventory"),
    "INVENTORY_INVOICE_MISSING": E(
        "Invoice Required", "This inventory entry requires a supplier invoice.",
        http=400, severity=WARNING, action={"type": "navigate", "target": "/procurement"},
        next_step="Attach the supplier invoice.", module="inventory"),
    "STOCK_ADJUSTMENT_SUCCESS": E(
        "Inventory Updated", "Inventory has been updated successfully.",
        http=200, success=True, severity=SUCCESS, module="inventory"),

    # ════════════════════════ PROCUREMENT ════════════════════════
    "PURCHASE_ORDER_CREATED": E(
        "PO Created", "Purchase order created successfully.",
        http=201, success=True, severity=SUCCESS, module="procurement"),
    "INVOICE_UPLOADED": E(
        "Invoice Saved", "The supplier invoice has been stored.",
        http=200, success=True, severity=SUCCESS, module="procurement"),
    "INVOICE_REQUIRED": E(
        "Invoice Required", "A supplier invoice must be uploaded.",
        http=400, severity=WARNING,
        next_step="Upload the invoice to continue.", module="procurement"),
    "SUPPLIER_INACTIVE": E(
        "Supplier Inactive", "Orders can't be created for inactive suppliers.",
        http=409, severity=WARNING,
        next_step="Reactivate the supplier or choose another.", module="procurement"),
    "RECEIVING_QTY_MISMATCH": E(
        "Quantity Mismatch", "The received quantity differs from the purchase order.",
        http=409, severity=WARNING,
        next_step="Reconcile the difference before closing.", module="procurement"),
    "PURCHASE_CLOSED": E(
        "Already Completed", "This purchase order has already been completed.",
        http=409, severity=INFO, module="procurement"),

    # ════════════════════════ STORE ADMIN ════════════════════════
    "STORE_DISABLED": E(
        "Store Inactive", "This store is currently inactive.",
        http=403, severity=WARNING, module="store"),
    "STORE_OUT_OF_STOCK": E(
        "Not In This Store", "The requested quantity is unavailable in this store.",
        http=409, severity=WARNING,
        next_step="Check another store or reduce the quantity.", module="store"),
    "MANAGER_APPROVAL_REQUIRED": E(
        "Approval Needed", "This action requires store manager approval.",
        http=403, severity=WARNING,
        next_step="Request manager approval to proceed.", module="store"),
    "DAILY_LIMIT_EXCEEDED": E(
        "Daily Limit Reached", "The permitted daily threshold has been exceeded.",
        http=429, severity=WARNING,
        next_step="Resume tomorrow or request an override.", module="store"),
    "STORE_INVENTORY_LOCKED": E(
        "Inventory Locked", "Inventory changes are temporarily locked.",
        http=423, severity=WARNING,
        next_step="Try again once the lock is released.", module="store"),

    # ════════════════════════ EMPLOYEE ════════════════════════
    "EMPLOYEE_INACTIVE": E(
        "Account Inactive", "This employee account is inactive.",
        http=403, severity=WARNING, action=SUPPORT, module="employee"),
    "EMPLOYEE_NOT_AUTHORIZED": E(
        "Not Authorized", "You don't have permission for this action.",
        http=403, severity=WARNING, module="employee", security=True),
    "SHIFT_NOT_STARTED": E(
        "Start Your Shift", "Start your shift before performing this action.",
        http=403, severity=WARNING, action={"type": "navigate", "target": "/shift"},
        next_step="Begin your shift to continue.", module="employee"),
    "SHIFT_CLOSED": E(
        "Shift Closed", "Your shift has already been closed.",
        http=409, severity=INFO, module="employee"),
    "ATTENDANCE_MISSING": E(
        "Mark Attendance", "Attendance must be recorded first.",
        http=403, severity=WARNING, action={"type": "navigate", "target": "/attendance"},
        next_step="Record your attendance to continue.", module="employee"),
    "LOCATION_OUTSIDE_STORE": E(
        "Wrong Location", "You must be at your assigned store location.",
        http=403, severity=WARNING,
        next_step="Move to the store and try again.", module="employee"),

    # ════════════════════════ SUPPORT / CRM ════════════════════════
    "TICKET_CREATED": E(
        "Ticket Raised", "Your support ticket has been created.",
        http=201, success=True, severity=SUCCESS,
        next_step="Our team typically responds within 24 hours.", module="support"),
    "TICKET_CLOSED": E(
        "Ticket Closed", "This ticket is closed.",
        http=409, severity=INFO,
        next_step="Raise a new ticket if you still need help.", module="support"),
    "FEEDBACK_RECEIVED": E(
        "Thanks For Your Feedback", "Your feedback has been recorded.",
        http=200, success=True, severity=SUCCESS, module="support"),

    # ════════════════════════ OFFERS / COUPONS ════════════════════════
    "COUPON_INVALID": E(
        "Invalid Coupon", "This coupon code isn't valid.",
        http=200, success=False, severity=WARNING,
        next_step="Check the code or try another offer.", module="offers"),
    "COUPON_EXPIRED": E(
        "Coupon Expired", "This coupon has expired.",
        http=200, success=False, severity=WARNING, module="offers"),
    "COUPON_MIN_NOT_MET": E(
        "Add More To Apply", "Your cart doesn't meet this coupon's minimum value.",
        http=200, success=False, severity=INFO, action=nav("/cart"),
        next_step="Add more items to unlock this offer.", module="offers"),
    "COUPON_APPLIED": E(
        "Coupon Applied", "Your discount has been applied.",
        http=200, success=True, severity=SUCCESS, module="offers"),
    "COUPON_LIMIT_REACHED": E(
        "Offer Fully Claimed", "This coupon has reached its usage limit.",
        http=409, severity=WARNING, action=nav("/cart"),
        next_step="Remove the coupon to continue, or try another offer.", module="offers"),
    "COUPON_ALREADY_USED": E(
        "Already Used", "You've already used this coupon.",
        http=409, severity=WARNING, action=nav("/cart"),
        next_step="Remove the coupon to continue.", module="offers"),

    # ── Banner management (v1.0) ──
    "UNSUPPORTED_IMAGE_TYPE": E(
        "Unsupported File", "Only JPG, PNG, and WebP images are allowed.",
        http=400, severity=WARNING, retryable=True,
        next_step="Upload a JPG, PNG, or WebP file.", module="offers"),
    "IMAGE_TOO_LARGE": E(
        "Image Too Large", "Banner images must be 3 MB or smaller.",
        http=400, severity=WARNING, retryable=True,
        next_step="Compress the image or upload a smaller file.", module="offers"),
    "IMAGE_INVALID": E(
        "Invalid Image", "The image couldn't be processed.",
        http=400, severity=WARNING, retryable=True,
        next_step="Upload a clear 2400×1200 (2:1) image.", module="offers"),
    "BANNER_SAVED": E(
        "Banner Saved", "The banner image has been processed and saved.",
        http=200, success=True, severity=SUCCESS, module="offers"),
    "BANNER_SUBMITTED": E(
        "Submitted For Approval", "The banner was submitted for super-admin approval.",
        http=200, success=True, severity=SUCCESS, module="offers"),
    "BANNER_APPROVED": E(
        "Banner Approved", "The banner has been approved and scheduled.",
        http=200, success=True, severity=SUCCESS, module="offers"),
    "BANNER_REJECTED": E(
        "Banner Rejected", "The banner was sent back to draft.",
        http=200, success=True, severity=INFO, module="offers"),
    "BANNER_STATE_CHANGED": E(
        "Banner Updated", "The banner state has been updated.",
        http=200, success=True, severity=SUCCESS, module="offers"),
    "BANNER_EVENTS_RECORDED": E(
        "Recorded", "Banner analytics events were recorded.",
        http=200, success=True, severity=INFO, module="offers"),
    "INVALID_BANNER_TRANSITION": E(
        "Action Not Allowed", "That change can't be made from the banner's current state.",
        http=409, severity=WARNING,
        next_step="Refresh and follow the banner workflow in order.", module="offers"),

    # ════════════════════════ LOYALTY / REFERRALS ════════════════════════
    "INSUFFICIENT_POINTS": E(
        "Not Enough Points", "You don't have enough points to redeem that amount.",
        http=400, severity=WARNING,
        next_step="Earn more points or redeem a smaller amount.", module="loyalty"),
    "POINTS_REDEEMED": E(
        "Points Redeemed", "Your points have been redeemed to your wallet.",
        http=200, success=True, severity=SUCCESS, module="loyalty"),
    "REFERRAL_ALREADY_APPLIED": E(
        "Already Applied", "You've already applied a referral code.",
        http=409, severity=INFO, module="referrals"),
    "REFERRAL_INVALID": E(
        "Invalid Code", "This referral code isn't valid.",
        http=400, severity=WARNING,
        next_step="Double-check the code and try again.", module="referrals"),
    "REFERRAL_APPLIED": E(
        "Referral Applied", "Your referral reward is on the way.",
        http=200, success=True, severity=SUCCESS, module="referrals"),

    # ════════════════════════ RETURNS ════════════════════════
    "RETURN_WINDOW_CLOSED": E(
        "Return Window Closed", "The return window for this order has closed.",
        http=409, severity=WARNING,
        next_step="Contact support if the item is defective.", module="returns"),
    "RETURN_NOT_ELIGIBLE": E(
        "Not Returnable", "This order isn't eligible for return.",
        http=409, severity=WARNING, module="returns"),
    "RETURN_CREATED": E(
        "Return Requested", "Your return request has been created.",
        http=201, success=True, severity=SUCCESS,
        next_step="We'll review it and arrange a pickup.", module="returns"),
    "RETURN_PHOTOS_REQUIRED": E(
        "Photos Needed", "Add at least one photo of the item you're returning.",
        http=400, severity=WARNING,
        next_step="Take a clear photo showing the item and its condition.",
        module="returns"),
    "RETURN_PICKUP_ASSIGNED": E(
        "Pickup Scheduled", "A pickup partner has been assigned to collect your return.",
        http=200, success=True, severity=SUCCESS,
        next_step="Keep the item and its packaging ready.", module="returns"),
    "RETURN_PICKUP_UNASSIGNED": E(
        "Pickup Pending", "No pickup partner is free right now — the store will "
        "assign one shortly.",
        http=200, success=True, severity=INFO,
        next_step="We'll notify you as soon as a partner is on the way.",
        module="returns"),
    "INVALID_RETURN_TRANSITION": E(
        "Action Not Allowed", "That isn't a valid next step for this pickup.",
        http=409, severity=ERROR,
        next_step="Refresh the task and try again.", module="returns"),
    "RETURN_EVIDENCE_REQUIRED": E(
        "Photo Required", "Capture a photo of the item's condition before "
        "completing this pickup.",
        http=400, severity=WARNING,
        next_step="Take at least one photo at the customer's door.",
        module="returns"),
    "RETURN_PICKUP_COMPLETED": E(
        "Return Collected", "The return has been collected and sent for refund.",
        http=200, success=True, severity=SUCCESS,
        next_step="The store will process the refund.", module="returns"),
    "RETURN_PICKUP_REJECTED": E(
        "Return Rejected", "The return was rejected at the customer's door.",
        http=200, success=True, severity=WARNING,
        next_step="The reason has been recorded for the customer.",
        module="returns"),
    "RETURN_PICKUP_RESCHEDULED": E(
        "Pickup Rescheduled", "The pickup has been deferred for another attempt.",
        http=200, success=True, severity=INFO,
        next_step="Try again at the rescheduled time.", module="returns"),
    "RETURN_QUANTITY_INVALID": E(
        "Invalid Quantity", "Accepted quantity can't exceed what the customer "
        "requested to return.",
        http=400, severity=ERROR, module="returns"),

    # ════════════════════════ REPORTING ════════════════════════
    "REPORT_GENERATING": E(
        "Preparing Report", "Your report is being generated.",
        http=202, success=True, severity=INFO,
        next_step="We'll notify you when it's ready.", module="reporting"),
    "REPORT_EMPTY": E(
        "No Data", "There's no data for the selected filters.",
        http=200, success=True, severity=INFO,
        next_step="Adjust the date range or filters.", module="reporting"),
}


def get(code: str) -> dict | None:
    return CATALOG.get(code)
