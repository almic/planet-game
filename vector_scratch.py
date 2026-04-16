from math import sqrt
from numpy import array as vec
from numpy.linalg import norm as v_len


vectors = vec([
    vec([-1.3, 0.1]),
    vec([0.9, 1.1]),
    vec([0.8, -0.7]),
    vec([-1.2, 1.5]),
    vec([-0.5, -1.2]),
    vec([0.3, 1.8])
])

def project(a, b):
    n = b / v_len(b)
    return n * (n @ a) 

results = vectors.copy()
total_len = 0.0
for i in range(len(vectors)):
    total_len += v_len(vectors[i])


MAX_ITERATIONS = 100
i = 0

print('Initial:')
print(vectors)

i_to_small = -1
last_c = -1

while i < MAX_ITERATIONS:
    i += 1

    m = results.sum(axis=0)

    next = results.copy()
    
    scale = 0.0

    # 3 Points
    if len(vectors) == 3:
        # m *= 1.0 - (1.0 / (2**min(i, 3))) # BAD!
        # m *= sqrt(2.0) / 2.0 # 36, 39
        # m *= 0.5 # 47, never
        # m *= 0.7 # 35, 37
        # m *= 0.65 # 31, 34
        m *= (2.0 / 3.0) # 20,31. BEST for 3? Why 2/3? freaky
    elif  len(vectors) == 4:
        m *= 0.5 # 22, 35. BEST for 4? freaky
    elif len(vectors) == 5:
        m *= 0.4 # 10, 16. BEST for 5? seeing the pattern
    elif len(vectors) == 6:
        m *= (1.0 / 3.0) # 14, 24. BEST for 6. Pattern found: 2 / count


    ## Method 1
    if True:
        for v in range(len(next)):
            next[v] = project(next[v] - m, vectors[v])
            scale += v_len(next[v])
    ## Method 2
    elif True:
        for v in range(len(next)):
            l = v_len(next[v] - m)
            next[v] *= l / v_len(next[v])
            scale += l

    scale = total_len / scale

    for v in range(len(next)):
        next[v] *= scale

    results = next

    if MAX_ITERATIONS < 5:
        print('\nIteration ' + str(i))
        print(results)
    else:
        c = v_len(results.sum(axis=0))
        if i_to_small == -1 and c < 1e-10:
            i_to_small = i
        if last_c == -1:
            last_c = c
        elif c > last_c:
            break
        else:
            last_c = c

conv = i

for i in range(len(results)):
    total_len -= v_len(results[i])

print('\nResult')
print(results)
print('D: ' + str(v_len(results.sum(axis=0))) + ', error: ' + str(total_len))
print('Small in ' + str(i_to_small) + ' iterations')
print('Converged in ' + str(conv) + ' iterations')

