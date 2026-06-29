import sys

with open(sys.argv[1], 'r') as f:
    c = f.read()

c = '#import "TKamiVerification.h"\n' + c
c = c.replace('[super viewDidLoad];', '[super viewDidLoad];\n\t[TKamiVerification checkVerificationIfNeededForViewController:self];', 1)

with open(sys.argv[1], 'w') as f:
    f.write(c)
print('Kami verification injected')
