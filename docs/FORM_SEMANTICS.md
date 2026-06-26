# Form Semantics

Current version: `v3.3.6`.

DesktopVisual v3.3.5 adds a small `FormControl` abstraction so option controls are not treated as text fields.

## FormControl

Each recognized control records:

- `field_id`
- `label`
- `control_type`
- `required`
- `options`
- `rect`
- `source`
- `confidence`
- `recommended_action`

Supported `control_type` values are `textbox`, `textarea`, `radio`, `checkbox`, `dropdown`, `combobox`, `button`, `link`, `date_picker`, `file_upload`, `code_editor`, `captcha/challenge`, and `unknown`.

## Action Mapping

- `textbox -> fill_text`
- `textarea -> fill_textarea`
- `radio -> select_radio`
- `checkbox -> toggle_checkbox`
- `dropdown/combobox -> select_option`
- `button -> click_button`
- `link -> click_link`
- `date_picker -> select_date`
- `file_upload -> select_file`
- `code_editor -> input_code`
- `captcha/challenge -> stop`
- `unknown -> stop`

Low-confidence or unknown fields are not treated as textboxes. Multiple matching fields return `FIELD_NOT_UNIQUE`. Captcha/challenge controls return `CAPTCHA_DETECTED`.

## Sources

v3.3.5 supports deterministic local HTML inspection through DOM-like visual hints (`id`, `name`, `type`, `label for`, `data-label`, `aria-label`, `data-control-type`, and select/radio options). The abstraction is designed to accept UIA, OCR, relative locator, and selector fallback sources as later extensions without changing the report shape.

## TaskRunner

Task files can use `type: "form_action"` with `html_path`, `field_id`, `label`, `value`, `option`, or explicit `control_type`. The report records the recognized `FormControl`, candidates, match count, mapped action, source, confidence, and result.

`form_action` still runs through WindowSession, PermissionManager, SafetyPolicy, Safety Manifest, and task reporting. It does not solve captcha, guess unknown fields, or submit sensitive flows.
