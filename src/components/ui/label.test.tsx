import assert from 'node:assert/strict'
import test from 'node:test'
import { renderToStaticMarkup } from 'react-dom/server'

import { Input } from './input'
import { FormField } from './label'

test('FormField associates its label, hint, and error with the supplied control', () => {
  const html = renderToStaticMarkup(
    <FormField
      label="Email address"
      htmlFor="email"
      hint="Use your work address"
      error="Enter a valid email"
      required
    >
      <Input id="email" name="email" type="email" aria-describedby="email-policy" />
    </FormField>,
  )

  assert.match(html, /<label[^>]*for="email"[^>]*>Email address/)
  assert.match(html, /<p[^>]*id="email-hint"[^>]*>Use your work address<\/p>/)
  assert.match(html, /<input[^>]*id="email"[^>]*aria-describedby="email-policy email-hint email-error"/)
  assert.match(html, /<input[^>]*aria-errormessage="email-error"[^>]*aria-invalid="true"/)
  assert.match(html, /<p[^>]*id="email-error"[^>]*role="alert"[^>]*>Enter a valid email<\/p>/)
})
