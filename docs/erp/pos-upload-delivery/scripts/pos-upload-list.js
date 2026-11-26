frappe.listview_settings['POS Upload'] = {
    add_fields: ['status'],
    has_indicator_for_draft: true,
    has_indicator_for_cancelled: true,

    get_indicator: function (doc) {
        // Status color map
        const status_map = {
            "Pending": "gray",
            "New": "blue",
            "In Progress": "purple",
            "To Deliver": "orange",
            "Out for Delivery": "blue",
            "Delivered": "green",
            "Completed": "green",
            "Cancelled": "red",
            "Rejected": "red"
        };

        const label = `${doc.status || 'Pending'}`;
        const color = status_map[label] || "gray";

        return [label, color, `status,=,${label}`];
    }
};
