#ifndef _E404_ATTRIBUTES_H
#define _E404_ATTRIBUTES_H

#include <linux/init.h>
#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/kobject.h>
#include <linux/sysfs.h>
#include <linux/sched.h>

struct e404_attributes {
    int effcpu;
    int rom_type;
    int dtbo_type;
    int batt_profile;
    int kgsl_skip_zeroing;
    int file_sync;
    int simple_thermal;
#ifdef CONFIG_BOARD_PIPA
    int panel_width_pipa;
    int panel_height_pipa;
    int panel_oem_width_pipa;
    int panel_oem_height_pipa;
#else 
    int panel_width;
    int panel_height;
    int panel_oem_width;
    int panel_oem_height;
#endif
};

extern struct e404_attributes e404_data;

extern int early_effcpu;
extern int early_rom_type;
extern int early_dtbo_type;
extern int early_batt_profile;

#endif /* _E404_ATTRIBUTES_H */
