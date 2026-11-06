import { parsePhoneNumberWithError, CountryCode } from 'libphonenumber-js';

export class PhoneService {
  /**
   * Normalizes a phone number to standard E.164 format (e.g. "+919876543210").
   * Strips whitespace, dashes, leading zeros, and invalid formatting.
   * Throws an error if the phone number is invalid.
   */
  public static normalizeToE164(rawPhone: string, defaultCountry: CountryCode = 'IN'): string {
    if (!rawPhone || typeof rawPhone !== 'string') {
      const err: any = new Error('Phone number must be a non-empty string');
      err.status = 400;
      throw err;
    }

    const trimmed = rawPhone.trim();

    try {
      const phoneNumber = parsePhoneNumberWithError(trimmed, defaultCountry);
      if (!phoneNumber.isValid()) {
        const err: any = new Error('Invalid phone number format');
        err.status = 400;
        throw err;
      }
      return phoneNumber.format('E.164');
    } catch (err: any) {
      const error: any = new Error(`Phone number normalization failed: ${err.message || 'Invalid format'}`);
      error.status = 400;
      throw error;
    }
  }

  /**
   * Validates if a string is a valid E.164 phone number.
   */
  public static isValid(rawPhone: string, defaultCountry: CountryCode = 'IN'): boolean {
    try {
      this.normalizeToE164(rawPhone, defaultCountry);
      return true;
    } catch {
      return false;
    }
  }
}

