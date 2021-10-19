def get_vartype_arg(wildcards):
    return "--select-type-to-include {}".format(
        "SNP" if wildcards.vartype == "snvs" else "INDEL")


rule select_calls:
    input:
        ref=config["ref"]["genome"],
        vcf=f"{OUTDIR}/genotyped/all.vcf.gz"
    output:
        vcf=temp(f"{OUTDIR}/filtered/all.{{vartype}}.vcf.gz")
    params:
        extra=get_vartype_arg
    log:
        f"{LOGDIR}/gatk/selectvariants/{{vartype}}.log"
    threads: get_resource("select_calls","threads")
    resources:
        mem_mb = get_resource("select_calls","mem"),
        walltime = get_resource("select_calls","walltime")
    wrapper:
        "0.79.0/bio/gatk/selectvariants"


def get_filter(wildcards):
    return {
        "snv-hard-filter":
        config["filtering"]["hard"][wildcards.vartype]}


rule hard_filter_calls:
    input:
        ref=config["ref"]["genome"],
        vcf=f"{OUTDIR}/filtered/all.{{vartype}}.vcf.gz"
    output:
        vcf=temp(f"{OUTDIR}/filtered/all.{{vartype}}.hardfiltered.vcf.gz")
    params:
        filters=get_filter
    threads: get_resource("hard_filter_calls","threads")
    resources:
        mem_mb = get_resource("hard_filter_calls","mem"),
        walltime = get_resource("hard_filter_calls","walltime")
    log:
        f"{LOGDIR}/gatk/variantfiltration/{{vartype}}.log"
    wrapper:
        "0.79.0/bio/gatk/variantfiltration"


rule recalibrate_calls:
    input:
        vcf=f"{OUTDIR}/genotyped/all.vcf.gz",
        ref=config["ref"]["genome"],
        hapmap=config["params"]["gatk"]["VariantRecalibrator"]["hapmap"],
        omni=config["params"]["gatk"]["VariantRecalibrator"]["omni"],
        g1k=config["params"]["gatk"]["VariantRecalibrator"]["g1k"],
        dbsnp=config["params"]["gatk"]["VariantRecalibrator"]["dbsnp"],
        aux=config["params"]["gatk"]["VariantRecalibrator"]["aux"]
    output:
        vcf=f"{OUTDIR}/filtered/all.both.recalibrated.vcf.gz",
        tranches=f"{OUTDIR}/filtered/all.tranches"
    params:
        mode="BOTH",
        resources=config["params"]["gatk"]["VariantRecalibrator"]["parameters"],
        annotation=config["params"]["gatk"]["VariantRecalibrator"]["annotation"],
        extra=config["params"]["gatk"]["VariantRecalibrator"]["extra"]
    log:
        f"{LOGDIR}/gatk/variantrecalibrator/log"
    threads: get_resource("recalibrate_calls","threads")
    resources:
        mem = get_resource("recalibrate_calls","mem"),
        walltime = get_resource("recalibrate_calls","walltime")
    wrapper:
        "0.79.0/bio/gatk/variantrecalibrator"

rule merge_calls:
    input:
        vcfs=expand(f"{OUTDIR}/filtered/all.{{vartype}}.{{filtertype}}.vcf.gz",
                   vartype=["both"]
                              if config["filtering"]["vqsr"]
                              else ["snvs", "indels"],
                   filtertype="recalibrated"
                              if config["filtering"]["vqsr"]
                              else "hardfiltered")
    output:
        vcf=f"{OUTDIR}/filtered/all.vcf.gz"
    log:
        f"{LOGDIR}/picard/merge-filtered.log"
    threads: get_resource("merge_calls","threads")
    resources:
        mem_mb = get_resource("merge_calls","mem"),
        walltime = get_resource("merge_calls","walltime")
    params:
        extra = ""
    wrapper:
        "0.79.0/bio/picard/mergevcfs"

rule filter_mutect_calls:
    input:
        vcf=f"{OUTDIR}/mutect/{{sample}}.vcf.gz",
        ref=config["ref"]["genome"]
    output:
        vcf=f"{OUTDIR}/mutect_filter/{{sample}}_passlable.vcf.gz"
    conda: "../envs/gatk.yaml"
    log:
        f"{LOGDIR}/gatk/mutect_filter.{{sample}}.log"
    shell:"""
        gatk FilterMutectCalls -R {input.ref} -V {input.vcf} -O {output}
    """

rule filter_mutect_2:
    input:
        vcf=f"{OUTDIR}/mutect_filter/{{sample}}_passlable.vcf.gz",
        ref=config["ref"]["genome"]
    output:
        vcf=f"{OUTDIR}/mutect_filter/{{sample}}_passlable_filtered.vcf.gz"
    params:
        filters={"DPfilter": config["filtering"]["depth"]}
    threads: get_resource("hard_filter_calls","threads")
    resources:
        mem_mb = get_resource("hard_filter_calls","mem"),
        walltime = get_resource("hard_filter_calls","walltime")
    log:
        f"{LOGDIR}/gatk/variantfiltration/{{sample}}_mutect.log"
    wrapper:
        "0.79.0/bio/gatk/variantfiltration"
