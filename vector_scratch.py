from math import sqrt
from math import fabs as abs
from numpy import array as vec
from numpy import empty
from numpy import append
from numpy.linalg import norm as v_len
from random import uniform

from decimal import Decimal as decimal

def drange(x, y, step):
    x = decimal(x)
    y = decimal(y)
    while x < y:
        yield float(x)
        x += decimal(step)


def normalize(v):
    l = v_len(v)
    if l == 0.0:
        return v
    return v / l

def project(a, b):
    l = v_len(b)
    if abs(l) < 1e-6:
        return b
    n = b / l
    return n * (n @ a) 

def iterate(result, original, length, multiplier = -1.0):
    rescale = 0.0
    count = len(original)

    midpoint = result.sum(axis=0)
    if multiplier != -1.0:
        midpoint *= multiplier
    elif count == 3:
        midpoint *= 2.0 / 3.0
    elif count == 4:
        midpoint *= 0.47
    else:
        midpoint *= 2.0 / count

    for i in range(count):
        result[i] = project(result[i] - midpoint, original[i])
        rescale += v_len(result[i])

    rescale = length / rescale

    for i in range(count):
        result[i] *= rescale

def converge(points, max_iterations = 100, do_print = False):
    results = points.copy()
    length = 0.0
    
    if do_print:
        print('Initial State:')
        print(points)
        print('Error: ' + str(length))

    last_error = -1

    target = generate_target(points)
    for i in range(len(points)):
        results[i] -= target

    for i in range(len(points)):
        length += v_len(results[i])

    for i in range(max_iterations):
        iterate(results, length)
        error = v_len(results.sum(axis=0))

        if do_print:
            print('\nIteration ' + str(i + 1))
            print(results)
            print('Error: ' + str(error))
        
        if last_error == -1 or error < last_error:
            last_error = error
        else:
            if do_print:
                print('Converged on iteration ' + str(i + 1))
            break

    if do_print:
        print('\nDone.')

    return results


def generate_points(count, dimensions, ranges):
    points = empty((0, dimensions))

    for i in range(count):
        p = vec([])
        for d in range(dimensions):
            p = append(p, uniform(ranges[d][0], ranges[d][1]))
        points = append(points, vec([p]), axis=0)

    return points

def generate_target(points):
    weight = uniform(0.0, 1.0)
    remainder = 1.0 - weight
    target = points[0] * weight
    for i in range(1, len(points)):
        if i == len(points) - 1:
            weight = remainder
        else:
            weight = uniform(0.0, remainder)
            remainder -= weight
        target += points[i] * weight
    return target


def run_tests(dim, min_points, max_points, tests, max_iterations):
    for count in range(min_points, max_points + 1):
        print('\nTesting ' + str(count) + ' points...')
        test_set = []

        for t in range(TESTS):
            points = []
            if dim == 2:
                points = generate_points(count, dim, [(-4.0, 4.0), (-4.0, 4.0)])
            elif dim == 3:
                points = generate_points(count, dim, [(-4.0, 4.0), (-2.0, 0.5), (-4.0, 4.0)])

            target = generate_target(points)
            for i in range(len(points)):
                points[i] -= target

            length = 0.0
            for i in range(len(points)):
                length += v_len(points[i])

            test_set.append((points, length))

        best_error = -1
        best_error_extra = 2
        for multiplier in drange(0.328, 0.336, 0.00025):
            print(multiplier, end=',')
            error_results = []
            for i in range(max_iterations):
                error_results.append((0.0, 0))

            for (points, length) in test_set:
                results = points.copy()
                last_error = -1
                for i in range(max_iterations):
                    #last_result = results.copy()
                    iterate(results, points, length, multiplier)
                    error = v_len(results.sum(axis=0))

                    #if not i in error_results:
                    #    error_results[i] = {'total': error, 'count': 1, 'final': 0.0, 'final_count': 0}
                    #else:
                    #    error_results[i][0] += error
                    #    error_results[i][1] += 1
                    error_results[i] = (error_results[i][0] + error, error_results[i][1] + 1)

                    if last_error == -1 or error < last_error:
                        last_error = error
                    else:
                        # Print first drop-out
                        #if False and error_results[i]['final_count'] == 0:
                        #    print('\nSample of drop-out on iteration ' + str(i + 1))
                        #    print('Original points:')
                        #    print(repr(points))
                        #    print('Last Two Results:')
                        #    print(repr(last_result))
                        #    print('Last Error: ' + str(last_error))
                        #    print(repr(results))
                        #    print('Error: ' + str(error))
                        #    input()
                        #error_results[i][2] += last_error
                        #error_results[i][3] += 1
                        break


            last_iter = len(error_results) - 1
            #for i in range(max_iterations + 1):
            #    if not i in error_results:
            #        i -= 1
            #        if i < 0:
            #            break
                    #error_results[i]['average'] = error_results[i]['total'] / float(error_results[i]['count'])
            avg = error_results[i][0] / float(error_results[i][1])
                    #if error_results[i]['final_count'] > 0:
                    #    error_results[i]['final_average'] = error_results[i]['final'] / float(error_results[i]['final_count'])
                    #print('\nIteration ' + str(i + 1))
                    #print(error_results[i])
                    #print(error_results[i]['average'])
            print(avg)
            if best_error == -1 or avg < best_error:
                best_error = avg
            else:
                best_error_extra -= 1
                    # print('\nNo iterations reached ' + str(i + 1))
                    #break

                # error_results[i]['average'] = error_results[i]['total'] / float(error_results[i]['count'])
                # if error_results[i]['final_count'] > 0:
                #     error_results[i]['final_average'] = error_results[i]['final'] / float(error_results[i]['final_count'])
                # print('\nIteration ' + str(i + 1))
                # print(error_results[i])

            if best_error_extra == 0:
                print('Error got worse, done')
                break

MIN_POINTS = 3
MAX_POINTS = 8
TESTS = 5
MAX_ITERATIONS = 100
#for dim in range(3, 4):
#    print('\n\nTesting in ' + str(dim) + 'D')
#    run_tests(dim, MIN_POINTS, MAX_POINTS, TESTS, MAX_ITERATIONS)

UP_IDX = 1

def test_gravity():

    body_mass = 64.0

    for point_count in range(5, 6):
        print('Testing ' + str(point_count) + ' legs...')

        #points = generate_points(point_count, 3, [(-1.5, 1.5), (-2.0, 2.0), (-1.0, 0.5)])
        #target = generate_target(points)
        #target[2] = 0.0
        
        points = vec([
            vec([-2.614, -0.727, 0.828]),
            vec([-1.705, -0.807, -0.878]),
            vec([-0.075, -0.807, 1.767]),
            vec([-0.78, -0.807, -1.772]),
            vec([1.493, -0.807, 1.565])
        ])
        target = vec([0.0, 0.0, 0.0])

        length = 0.0
        for p in range(point_count):
            points[p] -= target
            length += v_len(points[p])

        print(repr(points))

        last_error = points.sum(axis=0)
        last_error[UP_IDX] = 0.0
        last_error = v_len(last_error)
        print('Initial Error: ' + str(last_error))

        results = points.copy()
        last_results = None

        iterations = 0
        converged = False
        small_in = -1
        for i in range(32):
            last_results = results.copy()
            
            iterate_gravity(results, points, length)
            error = results.sum(axis=0)
            error[UP_IDX] = 0.0
            error = v_len(error)

            if error < last_error:
                last_error = error
                iterations += 1
                if small_in == -1 and error < 0.01:
                    small_in = iterations
            else:
                converged = True
                results = last_results
                break

        print('Results:\n' + repr(results))
        print('Error: ' + str(last_error))
        print('Iterations: ' + str(iterations))
        print('Till Small: ' + str(small_in))
        print('Converged: ' + str(converged))

        multipliers = []
        for p in range(point_count):
            multipliers.append(v_len(results[p]) / v_len(points[p]))
        print('Multipliers: ' + str(multipliers))

        
def iterate_gravity(result, original, length):
    rescale = 0.0
    count = len(original)

    midpoint = result.sum(axis=0)
    midpoint[UP_IDX] = 0.0
    midpoint *= 2.0 / count

    deltas = []
    delta_total = 0.0
    rescale = 0.0

    for i in range(count):
        deltas.append(v_len(result[i]))
        result[i] = project(result[i] - midpoint, original[i])
        new_len = v_len(result[i])
        rescale += new_len
        d = abs(deltas[i] - new_len)
        delta_total += d
        deltas[i] = d

    rescale = length - rescale

    # Normalize, map, rescale
    for i in range(count):
        deltas[i] /= delta_total
        result[i] = normalize(original[i]) * (v_len(result[i]) + (rescale * deltas[i]))

test_gravity()

