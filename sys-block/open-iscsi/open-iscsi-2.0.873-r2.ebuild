# Copyright 1999-2015 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2
# $Id$

EAPI=5

inherit versionator linux-info eutils flag-o-matic toolchain-funcs systemd

MY_PV="${PN}-$(replace_version_separator 2 "-" $MY_PV)"

DESCRIPTION="Open-iSCSI is a high performance, transport independent, multi-platform implementation of RFC3720"
HOMEPAGE="http://www.open-iscsi.org/"
SRC_URI="http://www.open-iscsi.org/bits/${MY_PV}.tar.gz"

LICENSE="GPL-2"
SLOT="0"
KEYWORDS="~alpha amd64 arm64 ~arm ~ia64 ~mips ~ppc ~ppc64 ~sparc x86"
IUSE="debug slp"

DEPEND="slp? ( net-libs/openslp )"
RDEPEND="${DEPEND}
	virtual/udev
	sys-fs/lsscsi
	sys-apps/util-linux"

S="${WORKDIR}/${MY_PV}"

pkg_setup() {
	linux-info_pkg_setup

	if kernel_is -lt 2 6 16; then
		ewarn "Sorry, your kernel must be 2.6.16-rc5 or newer!"
	fi

	# Needs to be done, as iscsid currently only starts, when having the iSCSI
	# support loaded as module. Kernel builtion options don't work. See this for
	# more information:
	# https://groups.google.com/group/open-iscsi/browse_thread/thread/cc10498655b40507/fd6a4ba0c8e91966
	# If there's a new release, check whether this is still valid!
	CONFIG_CHECK_MODULES="SCSI_ISCSI_ATTRS ISCSI_TCP"
	if linux_config_exists; then
		for module in ${CONFIG_CHECK_MODULES}; do
			linux_chkconfig_module ${module} || ewarn "${module} needs to be built as module (builtin doesn't work)"
		done
	fi
}

src_prepare() {
	epatch "${FILESDIR}"/${P}-Makefiles.patch
	epatch "${FILESDIR}"/${P}-remove-kernel-version-check.patch

	sed -i -e 's:^\(iscsid.startup\)\s*=.*:\1 = /usr/sbin/iscsid:' etc/iscsid.conf || die
	sed -i -e 's:^node.startup = manual:node.startup = automatic:' etc/iscsid.conf || die
}

src_configure() {
	cd utils/open-isns || die

	# SSL (--with-security) is broken
	econf $(use_with slp) \
		--without-security
}

src_compile() {
	use debug && append-flags -DDEBUG_TCP -DDEBUG_SCSI

	CFLAGS="" \
	emake \
		OPTFLAGS="${CFLAGS}" \
		AR="$(tc-getAR)" CC="$(tc-getCC)" \
		user
}

src_install() {
	emake DESTDIR="${D}" sbindir="usr/sbin/" install

	dodoc README THANKS

	docinto test/
	dodoc test/*

	# udev pieces
	insinto /usr/lib/udev/rules.d
	doins "${FILESDIR}"/99-iscsi.rules
	insopts -m0755
	insinto /usr/lib/udev/scripts
	doins "${FILESDIR}"/iscsidev.sh
	insopts -m0644

	systemd_dounit "${FILESDIR}"/iscsid.service
	systemd_dounit "${FILESDIR}"/iscsid.socket
	systemd_dounit "${FILESDIR}"/iscsid-initiatorname.service
	systemd_dotmpfilesd "${FILESDIR}"/open-iscsi.conf

	fperms 600 /etc/iscsi/iscsid.conf
	rm "${D}"/etc/iscsi/initiatorname.iscsi
	mv "${D}"/etc/iscsi "${D}"/usr/share/iscsi
}
