FROM registry.access.redhat.com/ubi9/ubi-minimal:9.5
RUN microdnf install -y gcc-toolset-12-gcc-c++ binutils
RUN printf '#include <mutex>\n#include <condition_variable>\nvoid test() {\n  std::mutex m;\n  std::condition_variable cv;\n  std::unique_lock<std::mutex> lk(m);\n  cv.wait(lk, []{ return true; });\n}\n' > /tmp/test.cpp
RUN /opt/rh/gcc-toolset-12/root/usr/bin/g++ -shared -fPIC -o /tmp/libtest_gcc12.so /tmp/test.cpp -std=c++17 && echo "Compiled OK"
RUN strings /tmp/libtest_gcc12.so | grep -E "GLIBC" | sort -u; echo "---"; strings /tmp/libtest_gcc12.so | grep GLIBCXX | sort -u
