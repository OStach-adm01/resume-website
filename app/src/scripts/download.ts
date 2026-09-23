import { normalizeCompany, validCompany } from '../lib/recruiter';
import { loadTurnstile } from '../lib/turnstile';

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
let token = '';
let widget: string | undefined;

async function securityCheck() {
  token = '';
  submit.disabled = true;
  try {
    const turnstile = await loadTurnstile();
    if (widget !== undefined) {
      turnstile.reset(widget);
      return;
    }
    widget = turnstile.render(
      document.querySelector<HTMLElement>('#turnstile-widget')!,
      {
        sitekey: trigger.dataset.siteKey!,
        action: 'resume-download',
        theme: 'dark',
        size: 'flexible',
        callback: (value) => {
          token = value;
          submit.disabled = pending;
        },
        'expired-callback': () => {
          token = '';
          submit.disabled = true;
          status.textContent = 'Security check expired. Please verify again.';
        },
        'error-callback': () => {
          token = '';
          submit.disabled = true;
          status.textContent =
            'Security check failed. Close this dialog and try again.';
        },
      },
    );
  } catch {
    status.textContent =
      'Security check unavailable. Close this dialog and try again.';
  }
}

trigger.addEventListener('click', () => {
  form.reset();
  companyField.hidden = true;
  company.required = false;
  status.textContent = '';
  requestId = crypto.randomUUID();
  dialog.showModal();
  void securityCheck();
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
  if (pending || !trigger.dataset.version || !token) return;
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
    status.textContent = 'Verifying and preparing your download…';
    const response = await fetch('/api/resume-download', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ token }),
      signal: AbortSignal.timeout(25000),
    });
    token = '';
    if (!response.ok) throw new Error('Download failed');
    const data = await response.json();
    const bytes = Uint8Array.from(atob(data.pdf), (character) =>
      character.charCodeAt(0),
    );
    const url = URL.createObjectURL(
      new Blob([bytes], { type: 'application/pdf' }),
    );
    link.href = url;
    link.download = 'Olgierd-Stach-Resume.pdf';
    document.body.append(link);
    link.click();
    link.remove();
    setTimeout(() => URL.revokeObjectURL(url), 60000);
    dialog.close();
  } catch {
    status.textContent =
      'We could not complete your request. Please verify again and retry. Your download has not started.';
    token = '';
    if (widget !== undefined) window.turnstile?.reset(widget);
  } finally {
    pending = false;
    submit.disabled = !token;
  }
});
