import { normalizeCompany, validCompany } from '../lib/recruiter';

const trigger = document.querySelector<HTMLButtonElement>('#download-resume')!;
const dialog = document.querySelector<HTMLDialogElement>('#recruiter-dialog')!;
const form = document.querySelector<HTMLFormElement>('#recruiter-form')!;
const companyField = document.querySelector<HTMLDivElement>('#company-field')!;
const company = document.querySelector<HTMLInputElement>('#company')!;
const status =
  document.querySelector<HTMLParagraphElement>('#download-status')!;
const submit = document.querySelector<HTMLButtonElement>('#confirm-download')!;
let requestId = '';
let pending = false;

trigger.addEventListener('click', () => {
  form.reset();
  companyField.hidden = true;
  company.required = false;
  status.textContent = '';
  requestId = crypto.randomUUID();
  dialog.showModal();
});
document.querySelector('.close-dialog')?.addEventListener('click', () => {
  if (!pending) dialog.close();
});
dialog.addEventListener('cancel', (event) => {
  if (pending) event.preventDefault();
});
form.addEventListener('change', () => {
  const yes = new FormData(form).get('recruiter') === 'yes';
  companyField.hidden = !yes;
  company.required = yes;
  company.setCustomValidity('');
});
company.addEventListener('input', () => company.setCustomValidity(''));
form.addEventListener('submit', async (event) => {
  event.preventDefault();
  if (pending || !trigger.dataset.version) return;
  const yes = new FormData(form).get('recruiter') === 'yes';
  if (yes && !validCompany(company.value)) {
    company.setCustomValidity(
      'Enter a company name between 2 and 120 characters.',
    );
    company.reportValidity();
    return;
  }
  pending = true;
  submit.disabled = true;
  try {
    if (yes) {
      status.textContent = 'Saving your request…';
      const response = await fetch('/api/recruiter-interest', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Idempotency-Key': requestId,
        },
        body: JSON.stringify({
          recruiter: true,
          companyName: normalizeCompany(company.value),
        }),
        signal: AbortSignal.timeout(10000),
      });
      if (!response.ok) throw new Error('Request failed');
    }
    const link = document.createElement('a');
    link.href = `/resume/${encodeURIComponent(trigger.dataset.version)}/resume.pdf`;
    link.download = 'Olgierd-Stach-Resume.pdf';
    document.body.append(link);
    link.click();
    link.remove();
    dialog.close();
  } catch {
    status.textContent =
      'We could not save your request. Please try again. Your download has not started.';
  } finally {
    pending = false;
    submit.disabled = false;
  }
});
