#!/bin/sh

if [ $# -eq 0 ] 
then
    echo "Usage: $0 <targets> ..."
    echo "  run <file.elf>       Simulate without logging"
    echo "  debug <file.elf>     Simulate with extensive logging"
    echo "  miv-run <file.elf>   Simulate Microsemi Mi-V memory map"
    echo "  miv-debug <file.elf> Simulate Micorsemi Mi-V with logging"
    echo "  tests                Run riscv-tests and riscv-compliance tests"
    echo
    echo "<file.elf>"
    echo "  ../../sw/picorv32-dhrystone/dhrystone.elf  Benchmark from picorv32 repo"
    echo "  ../../sw/riscv-dhrystone/dhrystone.elf     Benchmark from RISC-V repo"
    exit 1
fi

. ../../config_default.sh
[ ! -e ../../config.sh ] || . ../../config.sh

verilog_files="../../src/memory.v ../../src/regset33.v ../../src/csr.v ../../pipeline.v"
path_tests="../../sw/tests"
path_compliance="../../sw/compliance"



# compile Icarus Verilog simulation
#   $1 ELF filename
#   $2 arguments for iverilog
compile() {
    ${RV_PREFIX}objcopy -O binary $1 tmp.bin
    printf "@0 " > tmp.hex
    od -An -tx4 -w4 -v tmp.bin | cut -b2- >> tmp.hex
    $IVERILOG -o tmp.vvp -DCODE=\"tmp.hex\" $2 $verilog_files || exit 1
}



# run binary image and compare signature
#   $1 filename of ELF image
#   $2 filename of expected signature
check_sig() {
    compile $1 tb_tests.v
    $VVP -N tmp.vvp | sed -e '/^xxxxxxxx$/d' > tmp.sig

    diff --strip-trailing-cr $2 tmp.sig > tmp.diff
    if [ $? -ne 0 ]
    then
        printf "not "
        failed=$(($failed + 1))
    fi
    name=$(basename $1 .elf)
    echo "ok - $name"
}



# Compile and run the riscv-tests and riscv-compliance tests
# Output in TAP (Test Anything Protocol) format
target_tests() {

    # build binaries
    make -s -C ${path_tests} || exit 1
    make -s -C ${path_compliance} || exit 1

    # count tests
    echo "TAP version 13"
    count_tests=$(ls -afq ${path_tests}/build/*.elf | wc -l)
    count_compliance=$(ls -afq ${path_compliance}/build/*.elf | wc -l)
    total=$(( $count_tests + $count_compliance ))
    echo "1..${total}"
    failed=0

    for test in ${path_tests}/build/*.elf
    do
        check_sig ${test} ${path_tests}/ok.sig
    done

    for test in ${path_compliance}/build/*.elf
    do
        name=$(basename $test .elf)
        check_sig $test ${path_compliance}/references/${name}.reference_output
    done 

    if [ "${failed}" -eq 0 ]
    then
        echo "# All ${total} tests passed."
    else
        echo "# Failed ${failed} of ${total} tests"
    fi
}



while [ $# -ne 0 ]
do
    case $1 in
        run)
            compile $2 "tb_tests.v"
            $VVP -N tmp.vvp
            shift
            ;;
        debug)
            compile $2 "-DDEBUG tb_tests.v"
            $VVP -N tmp.vvp
            shift
            ;;
        miv-run)
            compile $2 "tb_miv.v"
            $VVP -N tmp.vvp
            shift
            ;;
        miv-debug)
            compile $2 "-DDEBUG tb_miv.v"
            $VVP -N tmp.vvp
            shift
            ;;
        tests)
            target_tests
            ;;
        *)
            echo "Unknown target $1. Stop."
            exit 2
            ;;
    esac
    shift
done