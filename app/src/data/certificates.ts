export interface Certificate {
  title: string;
  issuer: string;
  image: string;
  verificationUrl: string;
  category: string;
}

// Local images from Coursera; credentials selected from the owner's resume.
export const certificates: Certificate[] = [
  {
    title: 'IBM DevOps and Software Engineering Professional Certificate',
    issuer: 'IBM · Coursera',
    image: '/certificates/ibm-devops.jpg',
    verificationUrl:
      'https://www.coursera.org/account/accomplishments/specialization/OG7XTC9Q0CWA',
    category: 'DEVOPS / SOFTWARE ENGINEERING',
  },
  {
    title: 'AWS Cloud Solutions Architect Professional Certificate',
    issuer: 'Amazon Web Services · Coursera',
    image: '/certificates/aws-cloud.jpg',
    verificationUrl:
      'https://www.coursera.org/account/accomplishments/specialization/L0EBMK39LFOO',
    category: 'CLOUD ARCHITECTURE',
  },
  {
    title: 'Python for Everybody Specialization',
    issuer: 'University of Michigan · Coursera',
    image: '/certificates/python.jpg',
    verificationUrl:
      'https://www.coursera.org/account/accomplishments/specialization/CJKI5FPQFJOA',
    category: 'PYTHON / PROGRAMMING',
  },
];
