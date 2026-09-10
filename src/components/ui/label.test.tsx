import assert from 'node:assert/strict'
import test from 'node:test'
import { renderToStaticMarkup } from 'react-dom/server'

import { Input } from './input'
import { FormField } from './label'

test('FormField associates its visible label with the supplied control id', () => {
  const html = renderToStaticMarkup(
    <FormField label="Email address" htmlFor="email" required>
      <Input id="email" name="email" type="email" />
    </FormField>,
  )

  assert.match(html, /<label[^>]*for="email"[^>]*>Email address/)
  assert.match(html, /<input[^>]*id="email"/)
})
