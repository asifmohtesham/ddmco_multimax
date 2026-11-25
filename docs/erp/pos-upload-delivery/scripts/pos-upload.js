frappe.ui.form.on('POS Upload', {
	onload(frm) {
		frm.add_custom_button(
			__('Validate Serialised Quantity'),
			() => validate_serialised_quantity(frm),
			__('Actions')
		);
	},

	refresh(frm) {
		// Only allow (re)uploading while the document is still open for editing.
		if (!pos_is_pending(frm.doc)) return;

		const label = is_update_mode(frm) ? __('Update') : __('Upload');
		frm.add_custom_button(label, () => upload_pos_xml(frm));
	},

	async before_workflow_action(frm) {
		const action = frm.selected_workflow_action;
		if (!['Out for Delivery', 'Delivery Return', 'Delivered'].includes(action)) return;
		if (frm.pos_delivery_action_pending) {
			frappe.dom.unfreeze();
			throw new Error(__('A delivery action is already in progress.'));
		}

		const doc = frm.doc;
		const revision = doc.modified;
		let frozen = true;
		let submitted = false;
		frm.pos_delivery_action_pending = true;
		try {
			const options = await frappe.xcall('pos_upload_delivery_drivers', {
				name: doc.name,
				action,
			}, 'GET');
			assert_pos_action_revision(frm, doc, revision);
			if (!options?.drivers?.length) {
				frappe.throw(__('No active drivers are available.'));
			}

			frappe.dom.unfreeze();
			frozen = false;
			const values = await prompt_pos_delivery_action(action, options);
			if (!values) throw new Error(__('Delivery action cancelled.'));

			assert_pos_action_revision(frm, doc, revision);
			doc.pos_delivery_driver = values.pos_delivery_driver;
			if (action === 'Delivery Return') {
				doc.pos_delivery_reason = values.pos_delivery_reason;
			}
			watch_pos_delivery_request(frm, doc, revision, action);
			frappe.dom.freeze();
			submitted = true;
		} finally {
			if (!submitted) {
				clear_pos_delivery_action(frm, doc);
				if (frozen) frappe.dom.unfreeze();
			}
		}
	},

	after_workflow_action(frm) {
		clear_pos_delivery_action(frm, frm.doc);
	},
});

function assert_pos_action_revision(frm, doc, revision) {
	if (cur_frm !== frm || frm.doc !== doc || doc.modified !== revision || frm.is_dirty()) {
		frappe.throw(__('Reload this POS Upload and use Actions again.'));
	}
}

function prompt_pos_delivery_action(action, options) {
	const active_drivers = new Set(options.drivers.map((driver) => driver.name));
	for (const driver of options.drivers) {
		frappe.utils.add_link_title('Driver', driver.name, driver.full_name || driver.name);
	}
	const fields = [{
		fieldtype: 'Link',
		fieldname: 'pos_delivery_driver',
		label: __('Driver'),
		options: 'Driver',
		only_select: 1,
		reqd: 1,
		default: options.default_driver || '',
		get_query: () => ({ filters: { status: 'Active' } }),
	}];
	if (action === 'Delivery Return') {
		fields.push({
			fieldtype: 'Select',
			fieldname: 'pos_delivery_reason',
			label: __('Return Reason'),
			options: '\nLate\nRejected\nOther',
			reqd: 1,
		});
	}
	return new Promise((resolve) => {
		const dialog = new frappe.ui.Dialog({
			title: __(action),
			fields,
			primary_action_label: __('Record'),
			primary_action(values) {
				if (!active_drivers.has(values.pos_delivery_driver)) {
					frappe.msgprint(__('Select an active Driver.'));
					return;
				}
				resolve(values);
				dialog.hide();
			},
		});
		dialog.$wrapper.one('hidden.bs.modal', () => resolve(null));
		dialog.show();
	});
}

function clear_pos_delivery_action(frm, doc) {
	delete doc.pos_delivery_driver;
	delete doc.pos_delivery_reason;
	frm.selected_workflow_action = null;
	frm.pos_delivery_action_pending = false;
}

function watch_pos_delivery_request(frm, doc, revision, action) {
	// Core calls after_workflow_action only on success. Observe its one matching
	// request as well so failed actions cannot leave transient values on the form.
	const event = 'ajaxComplete.posUploadDelivery';
	$(document).on(event, function completed(_event, xhr, settings) {
		if (!settings.url.endsWith('/api/method/frappe.model.workflow.apply_workflow')) return;
		const args = new URLSearchParams(settings.data);
		if (args.get('action') !== action || !args.has('doc')) return;
		const sent = JSON.parse(args.get('doc'));
		if (sent.doctype !== 'POS Upload' || sent.name !== doc.name || sent.modified !== revision
			|| sent.pos_delivery_driver !== doc.pos_delivery_driver) return;

		$(document).off(event, completed);
		clear_pos_delivery_action(frm, doc);
		if (!xhr.responseJSON?.message && cur_frm === frm && frm.doc.name === doc.name) {
			frm.reload_doc();
		}
	});
}

// --- Constants -------------------------------------------------------------

const POS_DOCNAME_PREFIXES = ['KA-', 'ML-', 'KX-', 'MX-'];
const AMOUNT_TOLERANCE = 0.01;

// Pieces per Tally unit. Any unit not listed here is treated as Nos (1 piece).
const PCS_PER_UNIT = { DOZ: 12, PCS: 1, NOS: 1 };

// ERPNext UOM shown in the Rate UOM column for each Tally unit.
const ERP_UOM = { DOZ: 'Doz', PCS: 'Nos', NOS: 'Nos' };
const DEFAULT_UOM = 'Nos';

// --- Button handlers -------------------------------------------------------

function is_update_mode(frm) {
	const prefix = (frm.doc.name || '').substring(0, 3);
	return POS_DOCNAME_PREFIXES.includes(prefix);
}

function pos_is_pending(doc) {
	return !doc.status || doc.status === 'Pending';
}

function validate_serialised_quantity(frm) {
	// TODO: implement serialised-quantity validation against frm.doc.items.
	frappe.msgprint({
		title: __('Validate Serialised Quantity'),
		message: __('Not yet implemented.'),
		indicator: 'orange',
	});
}

async function upload_pos_xml(frm) {
	const doc = frm.doc;
	const revision = doc.modified;
	if (!pos_is_pending(doc)) return;
	const file = await pick_file('.xml', { class_name: 'upload-update' });
	if (!file) return;

	frappe.dom.freeze(__('Loading Tally XML…'));
	try {
		const raw_xml = await read_file_as_text(file);
		const xml_doc = parse_pos_xml(raw_xml);
		if (!frm.is_new()) {
			const { message: current } = await frappe.db.get_value(
				'POS Upload', doc.name, ['status', 'modified']
			);
			if (!current || !pos_is_pending(current) || current.modified !== revision) {
				throw new Error(__('Reload the POS Upload. Tally re-import is available only in Pending.'));
			}
		}
		if (cur_frm !== frm || frm.doc !== doc || doc.modified !== revision || !pos_is_pending(doc)) {
			throw new Error(__('Reload the POS Upload. Tally re-import is available only in Pending.'));
		}
		const warnings = await apply_pos_xml(frm, xml_doc);
		await frm.save();
		frappe.show_alert({ message: __('XML loaded successfully.'), indicator: 'green' });
		show_amount_warnings(warnings);
	} catch (error) {
		console.error(error);
		frappe.msgprint({
			title: __('Upload failed'),
			message: __('Could not process the XML file: {0}', [error.message]),
			indicator: 'red',
		});
	} finally {
		frappe.dom.unfreeze();
	}
}

// --- XML -> form -----------------------------------------------------------

async function apply_pos_xml(frm, xml_doc) {
	const { items, warnings } = build_items(xml_doc);
	frm.clear_table('items');
	items.forEach(row => frm.add_child('items', row));
	frm.refresh_field('items');

	const total_qty = items.reduce((sum, row) => sum + row.quantity, 0);
	const total_amount = items.reduce((sum, row) => sum + row.amount, 0);
	await frm.set_value({
		date: parse_tally_date(get_tag_text(xml_doc, 'DATE')),
		reference_no: get_tag_text(xml_doc, 'VOUCHERNUMBER'),
		customer: get_tag_text(xml_doc, 'PARTYLEDGERNAME'),
		total_qty,
		total_amount: +total_amount.toFixed(3),
	});

	return warnings;
}

function build_items(xml_doc) {
	const entries = Array.from(xml_doc.getElementsByTagName('ALLINVENTORYENTRIES.LIST'));
	const warnings = [];

	const items = entries.map((entry, index) => {
		const get = tag => get_tag_text(entry, tag);
		const item_name = get('STOCKITEMNAME');
		const rate = parse_tally_rate(get('RATE'));
		const quantity = parse_tally_qty_pcs(get('ACTUALQTY'));

		// Rate x quantity, with the quantity expressed in the rate's own unit.
		const expected = +((rate.value * quantity) / pcs_per_unit(rate.unit)).toFixed(3);

		// Tally's line amount is authoritative; the calculation is only a cross-check
		// (and the fallback when the XML carries no amount). Sign is dropped so that
		// amounts stay positive whichever way Tally posts the voucher.
		const tally_amount = parse_tally_number(get('AMOUNT'));
		const amount = isNaN(tally_amount) ? expected : +Math.abs(tally_amount).toFixed(3);

		if (Math.abs(amount - expected) > AMOUNT_TOLERANCE) {
			warnings.push(
				__('Row {0} ({1}): Tally amount {2} differs from rate x quantity {3}.', [
					index + 1,
					item_name,
					amount,
					expected,
				])
			);
		}

		return {
			item_name: item_name,
			ref_code: get('BASICUSERDESCRIPTION'), // customer code (e.g. 7-digit starting with 5)
			rate: rate.value, // as exported by Tally, per the unit in uom
			uom: to_erp_uom(rate.unit), // unit the rate is quoted in
			quantity: quantity, // nos
			amount: amount,
		};
	});

	return { items, warnings };
}

function show_amount_warnings(warnings) {
	// Informational only: the upload has already been saved with Tally's amounts.
	if (!warnings.length) return;
	frappe.msgprint({
		title: __('Amount mismatch'),
		message: warnings.join('<br>'),
		indicator: 'orange',
	});
}

// --- Tally units -----------------------------------------------------------

function pcs_per_unit(unit) {
	// Unknown or missing units are assumed to be Nos.
	return PCS_PER_UNIT[(unit || '').trim().toUpperCase()] || 1;
}

function to_erp_uom(unit) {
	// Unknown or missing units are assumed to be Nos, matching pcs_per_unit().
	return ERP_UOM[(unit || '').trim().toUpperCase()] || DEFAULT_UOM;
}

function is_known_unit(unit) {
	return (unit || '').trim().toUpperCase() in PCS_PER_UNIT;
}

function parse_tally_number(text) {
	return parseFloat((text || '').replace(/,/g, ''));
}

function parse_tally_rate(text) {
	// "220.00/DOZ" -> { value: 220, unit: 'DOZ' }
	const [value, unit] = (text || '').split('/');
	return { value: parse_tally_number(value) || 0, unit: (unit || '').trim() };
}

function parse_tally_qty_pcs(text) {
	// Tally states the quantity once per unit of the item, joined by "=":
	//   " 10.000 DOZ =  120 PCS" -> 120
	//   " 6 PCS"                 -> 6
	const parts = (text || '')
		.split('=')
		.map(part => part.trim().match(/^(-?[\d.,]+)\s*(.*)$/))
		.filter(Boolean)
		.map(match => ({ value: parse_tally_number(match[1]) || 0, unit: match[2] }));
	if (!parts.length) return 0;

	// Prefer a figure already in single pieces (exact); otherwise convert the first.
	const part =
		parts.find(p => is_known_unit(p.unit) && pcs_per_unit(p.unit) === 1) || parts[0];
	return Math.round(Math.abs(part.value) * pcs_per_unit(part.unit));
}

// --- Parsing helpers -------------------------------------------------------

function parse_pos_xml(raw_xml) {
	const cleaned = clean_xml(raw_xml);
	const xml_doc = new DOMParser().parseFromString(cleaned, 'text/xml');

	const parse_error = xml_doc.getElementsByTagName('parsererror')[0];
	if (parse_error) throw new Error(parse_error.textContent.trim());

	return xml_doc;
}

function get_tag_text(node, tag) {
	const el = node.getElementsByTagName(tag)[0];
	return el ? el.textContent.trim() : '';
}

function parse_tally_date(yyyymmdd) {
	// Tally exports dates as YYYYMMDD, which is already ISO once hyphenated.
	if (!yyyymmdd || yyyymmdd.length < 8) return null;
	return `${yyyymmdd.slice(0, 4)}-${yyyymmdd.slice(4, 6)}-${yyyymmdd.slice(6, 8)}`;
}

function clean_xml(xml_text) {
	return xml_text
		// Remove invalid XML control characters.
		.replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F]/g, '')
		// Drop numeric character references to invalid XML chars (e.g. Tally's &#4;).
		.replace(/&#(x[0-9a-fA-F]+|[0-9]+);/g, (match, code) => {
			const cp = /^x/i.test(code) ? parseInt(code.slice(1), 16) : parseInt(code, 10);
			return is_valid_xml_char(cp) ? match : '';
		})
		// Escape bare ampersands that are not already part of a valid entity.
		.replace(/&(?!amp;|lt;|gt;|apos;|quot;|#[0-9]+;|#x[0-9a-fA-F]+;)/g, '&amp;')
		// Trim BOM / stray whitespace.
		.trim();
}

function is_valid_xml_char(cp) {
	// Valid XML 1.0 characters (https://www.w3.org/TR/xml/#charsets).
	return (
		cp === 0x9 ||
		cp === 0xa ||
		cp === 0xd ||
		(cp >= 0x20 && cp <= 0xd7ff) ||
		(cp >= 0xe000 && cp <= 0xfffd) ||
		(cp >= 0x10000 && cp <= 0x10ffff)
	);
}

// --- Browser helpers -------------------------------------------------------

function pick_file(accept, { class_name } = {}) {
	return new Promise(resolve => {
		const input = document.createElement('input');
		input.type = 'file';
		input.accept = accept;
		if (class_name) input.classList.add(class_name);
		input.addEventListener('change', event => resolve(event.target.files[0] || null));
		input.click();
	});
}

function read_file_as_text(file) {
	return new Promise((resolve, reject) => {
		const reader = new FileReader();
		reader.onload = event => resolve(event.target.result);
		reader.onerror = () => reject(reader.error);
		reader.readAsText(file);
	});
}

function get_status_color(status) {
	const colors = {
		Pending: 'orange',
		New: 'blue',
		'In Progress': 'purple',
		'To Deliver': 'orange',
		'Out for Delivery': 'blue',
		Delivered: 'green',
		Completed: 'green',
		Cancelled: 'gray',
		Rejected: 'red',
	};
	return colors[status] || 'gray';
}
