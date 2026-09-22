export interface Certificate {
  title: string;
  issuer: string;
  image: string;
  verificationUrl: string;
  category: string;
}

// Add your own images to app/public/certificates and entries below.
// The website does not fetch or verify external credential links.
export const certificates: Certificate[] = [];
