#!/usr/bin/python

"""
This script takes a .dat file from the Elite/Oolite source
and exports a .mesh file containing the same geometry.

Polygons with more than 3 edges have to be exported as a series of triangles
v0 v1 v2 v3 ... vn  map to (v0 v1 v2) (v0 v2 v3) ... (v0 vn-1 vn)

Edges are calculated for each triangle.

Material for the faces is set to flat white (127,127,127)
and surface normals need not be calculated.
"""

import sys, string, math

inputfilenames = sys.argv[1:]
print "converting..."
print inputfilenames
for inputfilename in inputfilenames:
	outputfilename = inputfilename.lower().replace(".dat",".mesh")
	print inputfilename+"->"+outputfilename
	inputfile = open(inputfilename,"r")
	lines = inputfile.read().splitlines(0)
	outputfile = open(outputfilename,"w")
	mode = 'SKIP'
	vertex_lines_out = ['VERTICES\r']
	tris_lines_out = ['MATERIAL\t65535\t65535\t65535\t0\t0\t0\r']
	extra_lines_out = []
	extra_lines_out.append(	'MATERIAL\t0\t0\t65535\t0\t0\t0\r')
	extra_lines_out.append(	'MATERIAL\t0\t65535\t0\t0\t0\t0\r')
	extra_lines_out.append(	'MATERIAL\t0\t65535\t65535\t0\t0\t0\r')
	extra_lines_out.append(	'MATERIAL\t65535\t0\t0\t0\t0\t0\r')
	extra_lines_out.append(	'MATERIAL\t65535\t0\t65535\t0\t0\t0\r')
	extra_lines_out.append(	'MATERIAL\t65535\t65535\t0\t0\t0\t0\r')
	extra_lines_out.append(	'MATERIAL\t32768\t32768\t32768\t0\t0\t0\r'	)
	n_verts = 0
	n_v = 0
	n_faces = 0
	n_f = 0
	skips = 0
	vertex=[]
	edge=[]
	triangle=[]
	for line in lines:
		if (mode == 'VERTEX'):
			coordinates = string.split(line, ',')	# split line by commas
			if (len(coordinates) == 3):
				x = float(coordinates[0])
				y = float(coordinates[1])
				z = float(coordinates[2])
				vertex.append( (x, y, z) )
				vertex_lines_out.append('%d\t%f\t%f\t%f\r' % (n_v, x, y, z))
				n_v = n_v + 1;
		elif (mode == 'FACES'):
			tokens = string.split(line, ',')	# split line by commas
			if (len(tokens) > 9) :
				color_data = tokens[0:3]
				normal_data =tokens[3:6]
				n_points = tokens[6]
				point_data = tokens[7:]
				v1 = int(point_data[0])
				v2 = int(point_data[1])
				v3 = int(point_data[2])
				d0 = (vertex[v2][0]-vertex[v1][0], vertex[v2][1]-vertex[v1][1], vertex[v2][2]-vertex[v1][2])
				d1 = (vertex[v3][0]-vertex[v2][0], vertex[v3][1]-vertex[v2][1], vertex[v3][2]-vertex[v2][2])
				xp = (d0[1]*d1[2]-d0[2]*d1[1], d0[2]*d1[0]-d0[0]*d1[2], d0[0]*d1[1]-d0[1]*d1[0])
				det = 1.0 / math.sqrt(xp[0]*xp[0] + xp[1]*xp[1] + xp[2]*xp[2])
				norm = (xp[0]*det, xp[1]*det, xp[2]*det)
				if ((norm[0]*float(normal_data[0]) < 0)|(norm[1]*float(normal_data[1]) < 0)|(norm[2]*float(normal_data[2]) < 0)) :
					point_data.reverse()
				v1 = int(point_data[0])
				while (len(point_data) >= 3) :
					v2 = int(point_data[1])
					v3 = int(point_data[2])
					edge1 = (v1, v2)
					edge2 = (v1, v3)
					edge3 = (v2, v3)
					if (edge.count(edge1) == 0) :
						edge.append(edge1)
					if (edge.count(edge2) == 0) :
						edge.append(edge2)
					if (edge.count(edge3) == 0) :
						edge.append(edge3)
					triangle.append( (v1,v2,v3) )
					tris_lines_out.append('%d\t%d\t%d\r' % (v1,v2,v3))
					point_data = point_data[1:]	#	move on a point
				#
		elif (mode == 'SKIP'):
			skips = skips + 1
		#
		if (line[:6] == 'NVERTS'):
			mode = 'SKIP'
		if (line[:6] == 'NFACES'):
			mode = 'SKIP'
		if (line[:6] == 'VERTEX'):
			mode = 'VERTEX'
		if (line[:5] == 'FACES'):
			mode = 'FACES'
		#
	outputfile.write('Mesh\t1\t1\r')
	outputfile.writelines(vertex_lines_out)
	outputfile.write('EDGES\r')
	for v0 in range(len(vertex)):
		for v1 in range(len(vertex)):
			if (edge.count((v0,v1)) > 0):
				outputfile.write('%d\t%d\r' % (v0,v1))
				edge.remove((v0,v1))
	outputfile.writelines(tris_lines_out)
	outputfile.writelines(extra_lines_out)
	outputfile.write('END\r')
	outputfile.close();
print "done"
print ""
#
#	end
#
