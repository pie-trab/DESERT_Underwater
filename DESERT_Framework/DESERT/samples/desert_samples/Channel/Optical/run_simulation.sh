# Change range
for i in $(seq 10 5 200)
do
    ns test_uwoptical_prop.tcl 0 0.1 125 $i -119
done

# Change depth
# for i in $(seq -5 -10 -200)
# do
#     ns test_uwoptical_prop.tcl 0 0.1 125 30 $i
# done
