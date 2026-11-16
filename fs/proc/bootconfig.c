// SPDX-License-Identifier: GPL-2.0
/*
 * /proc/bootconfig - Extra boot configuration
 */
#include <linux/fs.h>
#include <linux/init.h>
#include <linux/printk.h>
#include <linux/proc_fs.h>
#include <linux/seq_file.h>
#include <linux/bootconfig.h>
#include <linux/slab.h>

static char *saved_boot_config;

static int boot_config_proc_show(struct seq_file *m, void *v)
{
	if (saved_boot_config)
		seq_puts(m, saved_boot_config);
	return 0;
}

/* Rest size of buffer */
#define rest(dst, end) ((end) > (dst) ? (end) - (dst) : 0)

/* Return the needed total length if @size is 0 */
static int __init copy_xbc_key_value_list(char *dst, size_t size)
{
	struct xbc_node *leaf, *vnode;
	char *key, *end = dst + size;
	const char *val;
	char q;
	int ret = 0;

	key = kzalloc(XBC_KEYLEN_MAX, GFP_KERNEL);
	if (!key)
		return -ENOMEM;

	xbc_for_each_key_value(leaf, val) {
		ret = xbc_node_compose_key(leaf, key, XBC_KEYLEN_MAX);
		if (ret < 0)
			break;
		ret = snprintf(dst, rest(dst, end), "%s = ", key);
		if (ret < 0)
			break;
		dst += ret;
		vnode = xbc_node_get_child(leaf);
		if (vnode) {
			xbc_array_for_each_value(vnode, val) {
				if (strchr(val, '"'))
					q = '\'';
				else
					q = '"';
				ret = snprintf(dst, rest(dst, end), "%c%s%c%s",
					q, val, q, xbc_node_is_array(vnode) ? ", " : "\n");
				if (ret < 0)
					goto out;
				dst += ret;
			}
		} else {
			ret = snprintf(dst, rest(dst, end), "\"\"\n");
			if (ret < 0)
				break;
			dst += ret;
		}
	}
out:
	kfree(key);

	return ret < 0 ? ret : dst - (end - size);
}

static int __init proc_boot_config_init(void)
{
	int len;
#if defined(CONFIG_BOOTCONFIG_HWC_IS_PRODUCT_SKU)
	const char *HWC_KEY = "androidboot.hwc = ";
	const char *SKU_KEY = "androidboot.product.hardware.sku = ";
	char hwc_value[64] = { 0 };
	char *hwc_line, *hwc_quote_start, *hwc_quote_end;
	char *sku_line, *sku_quote_start, *sku_quote_end;
	size_t hwc_len, sku_old_len, sku_new_len;
#endif

	len = copy_xbc_key_value_list(NULL, 0);
	if (len < 0)
		return len;

	if (len > 0) {
		saved_boot_config = kzalloc(len + 1, GFP_KERNEL);
		if (!saved_boot_config)
			return -ENOMEM;

		len = copy_xbc_key_value_list(saved_boot_config, len + 1);
		if (len < 0) {
			kfree(saved_boot_config);
			return len;
		}

#if defined(CONFIG_BOOTCONFIG_HWC_IS_PRODUCT_SKU)
		hwc_line = strstr(saved_boot_config, HWC_KEY);
		if (!hwc_line)
			goto skip;

		hwc_quote_start = strchr(hwc_line, '"');
		if (!hwc_quote_start)
			goto skip;
		hwc_quote_start++;
		hwc_quote_end = strchr(hwc_quote_start, '"');
		if (!hwc_quote_end || hwc_quote_end <= hwc_quote_start)
			goto skip;

		hwc_len = hwc_quote_end - hwc_quote_start;
		if (hwc_len >= sizeof(hwc_value))
			hwc_len = sizeof(hwc_value) - 1;
		strncpy(hwc_value, hwc_quote_start, hwc_len);
		hwc_value[hwc_len] = '\0';
		if (!hwc_value[0])
			goto skip;

		sku_line = strstr(saved_boot_config, SKU_KEY);
		if (!sku_line)
			goto skip;

		sku_quote_start = strchr(sku_line, '"');
		if (!sku_quote_start)
			goto skip;
		sku_quote_start++;
		sku_quote_end = strchr(sku_quote_start, '"');
		if (!sku_quote_end || sku_quote_end <= sku_quote_start)
			goto skip;

		sku_old_len = sku_quote_end - sku_quote_start;
		sku_new_len = strlen(hwc_value);
		if (sku_new_len <= sku_old_len) {
			memmove(sku_quote_start + sku_new_len, sku_quote_end,
				strlen(sku_quote_end) + 1);
			memcpy(sku_quote_start, hwc_value, sku_new_len);
		} else {
			memcpy(sku_quote_start, hwc_value, sku_old_len);
		}
#endif
	skip:;
	}

	proc_create_single("bootconfig", 0, NULL, boot_config_proc_show);

	return 0;
}
fs_initcall(proc_boot_config_init);
