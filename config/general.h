#define IMAGE_BZIMAGE           /* Linux bzImage image support */
#define IMAGE_TRUST_CMD         /* Image trust management commands */
#define DOWNLOAD_PROTO_HTTPS    /* Secure Hypertext Transfer Protocol */
#define POWEROFF_CMD            /* Power off command */

#undef  DOWNLOAD_PROTO_TFTP     /* Trivial File Transfer Protocol */
#undef  SANBOOT_PROTO_ISCSI     /* iSCSI protocol */
#undef  SANBOOT_PROTO_AOE       /* AoE protocol */
#undef  SANBOOT_PROTO_IB_SRP    /* Infiniband SCSI RDMA protocol */
#undef  SANBOOT_PROTO_FCP       /* Fibre Channel protocol */
#undef  SANBOOT_PROTO_HTTP      /* HTTP SAN protocol */

#undef  IBMGMT_CMD              /* Infiniband management commands */
#undef  FCMGMT_CMD              /* Fibre Channel management commands */
#undef  SANBOOT_CMD             /* SAN boot commands */

