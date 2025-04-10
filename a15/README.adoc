# How to use

## NXP Resources

* Download page:
https://www.nxp.com/design/design-center/software/embedded-software/i-mx-software/android-os-for-i-mx-applications-processors:IMXANDROID
* User Guide:
https://www.nxp.com/docs/en/user-guide/ANDROID_USERS_GUIDE.pdf

## Prepare the modified repositories

```
cd ${MY_ANDROID}
git -C device/nxp remote add compulab https://github.com/vraevsky/imx-android.git
git -C device/nxp remote update
git -C device/nxp checkout remotes/compulab/compulab-imx8-android-15-rc1

git -C vendor/nxp-opensource/kernel_imx remote add compulab https://github.com/vraevsky/linux-imx.git
git -C vendor/nxp-opensource/kernel_imx remote update
git -C vendor/nxp-opensource/kernel_imx remote checkout remotes/compulab/compulab-imx8-android-15-rc1

git -C vendor/nxp-opensource/uboot-imx remote add compulab https://github.com/vraevsky/uboot-imx.git
git -C vendor/nxp-opensource/uboot-imx remote update
git -C vendor/nxp-opensource/uboot-imx checkout remotes/compulab/u-boot-compulab_v2023.04-a15
```

## Apply the u-boot changes in order to pass the andriod boot process
```
sed -i '/BINMAN/d' vendor/nxp-opensource/uboot-imx/board/compulab/plat/Kconfig
sed -i 's/ifdef CONFIG_SPL_OS_BOOT/if 1/g' vendor/nxp-opensource/uboot-imx/board/compulab/plat/imx8mp/ddr/ddr.h
```

## CompuLab imx8mp u-boot external build how to

### Prerequisites
It is up to developers to prepare the host machine; it requires:

* [Setup Cross Compiler](https://github.com/compulab-yokneam/meta-bsp-imx8mp/blob/kirkstone/Documentation/toolchain.md#linaro-toolchain-how-to)
* Install these packages: ``shareutils, swing``

* Create U-boot binary
```
cd ${MY_ANDROID}/vendor/nxp-opensource/uboot-imx
export BUILD=$(pwd)/../uboot-imx-build.d
# roll back the android sed changes
git checout .
make O=${BUILD} ucm-imx8m-plus_android_defconfig
make O=${BUILD} flash.bin
export COMPULAB_UBOOT=$(readlink -e ${BUILD}/flash.bin)
cd -
```

* Copy the U-boot file to the Android output folder
```
cp -v ${COMPULAB_UBOOT} ${MY_ANDROID}/out/target/product/ucm_imx8m_plus/u-boot-imx8mp.imx
```

* A15 build

** mini
```
lunch ucm_imx8m_mini-nxp_stable-userdebug
```

** plus
```
lunch ucm_imx8m_plus-nxp_stable-userdebug
```
