#!/usr/bin/python

"""
This script takes a Wavefront .obj file
and exports a .dat file containing the same trimesh.

Colour for the faces is set to flat grey (127,127,127)
and surface normals calculated for each triangle.
"""

import sys, string, math

def vertex_reference(n, nv):
	if (n < 0):
		return n + nv
	return n - 1

inputfilenames = sys.argv[1:]
print "converting..."
print inputfilenames
for inputfilename in inputfilenames:
	outputfilename = inputfilename.lower().replace(".obj", ".dat")
	if (outputfilename == inputfilename):
		outputfilename = outputfilename,append(".1")
	print inputfilename+"->"+outputfilename
	inputfile = open( inputfilename, "r")
	lines = inputfile.read().splitlines(0)
	outputfile = open( outputfilename, "w")
	mode = 'SKIP'
	vertex_lines_out = ['VERTEX\n']
	faces_lines_out = ['FACES\n']
	n_verts = 0
	n_faces = 0
	skips = 0
	vertex=[]
	uv=[]
	face=[]
	texture=[]
	uvForVertex=[]
	uvsForTexture={}
	textureForFace=[]
	uvsForFace=[]
	textureCounter = 0
	interpretTexture = 0
	materials = {}
	max_v = [0.0, 0.0, 0.0]
	min_v = [0.0, 0.0, 0.0]
	# find materials from mtllib
	for line in lines:
		tokens = string.split(line)
		#print "line :"
		#print line
		#print "tokens :"
		#print tokens
		if (tokens != []):
			if (tokens[0] == 'mtllib'):
				path = string.split(inputfilename, '/')
				path[-1] = tokens[1]
				materialfilename = string.join(path,'/')
				print "going to open material library file: %s" % materialfilename
				infile = open( materialfilename, "r")
				mlines = infile.read().splitlines(0)
				newMaterial = 0
				for mline in mlines:
					tokens1 = string.split(mline)
					if (tokens1[0] == 'newmtl'):
						newMaterialName = tokens1[1]
						newMaterial = 1
					if (tokens1[0] == 'map_Kd'):
						if (newMaterial):
							materials[newMaterialName] = tokens1[1]
							print "Material %s -> %s" % (newMaterialName, tokens1[1])
						newMaterial = 0
	#print "materials :"
	#print materials
	# find geometry vertices first
	for line in lines:
		tokens = string.split(line)
		if (tokens != []):
			if (tokens[0] == 'v'):
				n_verts = n_verts + 1
				# negate x value for vertex to allow correct texturing...
				x = -float(tokens[1])
				y = float(tokens[2])
				z = float(tokens[3])
				vertex.append( ( x, y, z) )
				vertex_lines_out.append('%.5f, %.5f, %.5f\n' % ( x, y, z))
				if (x > max_v[0]):
					max_v[0] = x
				if (y > max_v[1]):
					max_v[1] = y
				if (z > max_v[2]):
					max_v[2] = z
				if (x < min_v[0]):
					min_v[0] = x
				if (y < min_v[1]):
					min_v[1] = y
				if (z < min_v[2]):
					min_v[2] = z
	#print "vertex:"
	#print vertex, len(vertex), n_verts
	#print "\n"
	# find texture coordinates next
	for line in lines:
		tokens = string.split(line)
		if (tokens != []):
			if (tokens[0] == 'vt'):
				uv.append( ( float(tokens[1]), 1.0 - float(tokens[2])) )
	#print "uv:"
	#print uv, len(uv), n_verts
	#print "\n"
	# find faces next
	# use red colour to show smoothing groups
	smoothing_group = 127
	for line in lines:
		tokens = string.split(line)
		if (tokens != []):
			if (tokens[0] == 's'):
				# we just step through the groups not bothering to check the group number
				smoothing_group = smoothing_group + 1
				if (smoothing_group > 255):
					smoothing_group = 0
			if (tokens[0] == 'usemtl'):
				textureName = tokens[1]
				if (materials.has_key(textureName)):
					textureName = materials[textureName]
				interpretTexture = 1
				texture.append(textureName)
				uvsForTexture[textureName] = n_verts * [[]]
			if (tokens[0] == 'f'):
				#print "line: %s" % line
				while (len(tokens) >=4):
					bits = string.split(tokens[1], '/')
					v1 = vertex_reference(int(bits[0]), n_verts)
					if (bits[1] > ''):
						vt1 = vertex_reference(int(bits[1]), n_verts)
					bits = string.split(tokens[2], '/')
					v2 = vertex_reference(int(bits[0]), n_verts)
					if (bits[1] > ''):
						vt2 = vertex_reference(int(bits[1]), n_verts)
					bits = string.split(tokens[3], '/')
					v3 = vertex_reference(int(bits[0]), n_verts)
					if (bits[1] > ''):
						vt3 = vertex_reference(int(bits[1]), n_verts)
					else:
						interpretTexture = 0
					#print "face (geometry): %d %d %d" % (v1, v2, v3)
					#print "face (textures): %d %d %d\n" % (vt1, vt2, vt3)
					d0 = (vertex[v2][0]-vertex[v1][0], vertex[v2][1]-vertex[v1][1], vertex[v2][2]-vertex[v1][2])
					d1 = (vertex[v3][0]-vertex[v2][0], vertex[v3][1]-vertex[v2][1], vertex[v3][2]-vertex[v2][2])
					xp = (d0[1]*d1[2]-d0[2]*d1[1], d0[2]*d1[0]-d0[0]*d1[2], d0[0]*d1[1]-d0[1]*d1[0])
					det = math.sqrt(xp[0]*xp[0] + xp[1]*xp[1] + xp[2]*xp[2])
					if (det > 0):
						n_faces = n_faces + 1
					#	norm = (xp[0]/det, xp[1]/det, xp[2]/det)
					# negate the normal to allow correct texturing...
						norm = ( -xp[0]/det, -xp[1]/det, -xp[2]/det)
						face.append((v1,v2,v3))
						faces_lines_out.append('%d,127,127,\t%.5f,%.5f,%.5f,\t3,\t%d,%d,%d\n' % (smoothing_group,norm[0],norm[1],norm[2],v1,v2,v3))
						if (interpretTexture):
							textureForFace.append(textureName)
							uvsForTexture[textureName][v1] = uv[vt1]
							uvsForTexture[textureName][v2] = uv[vt2]
							uvsForTexture[textureName][v3] = uv[vt3]
							uvsForFace.append([ uv[vt1], uv[vt2], uv[vt3]])
					tokens = tokens[:2]+tokens[3:]
	# begin final output...
	outputfile.write('// output from Obj2DatTex.py Wavefront text file conversion script\n')
	outputfile.write('// (c) 2005 By Giles Williams\n')
	outputfile.write('// \n')
	outputfile.write('// original file: "%s"\n' % inputfilename)
	outputfile.write('// \n')
	outputfile.write('// model size: %.3f x %.3f x %.3f\n' % ( max_v[0]-min_v[0], max_v[1]-min_v[1], max_v[2]-min_v[2]))
	outputfile.write('// \n')
	outputfile.write('// textures used: %s\n' % uvsForTexture.keys())
	outputfile.write('// \n')
	outputfile.write('NVERTS %d\n' % n_verts)
	outputfile.write('NFACES %d\n' % n_faces)
	outputfile.write('\n')
	outputfile.writelines(vertex_lines_out)
	outputfile.write('\n')
	outputfile.writelines(faces_lines_out)
	outputfile.write('\n')
	# check that we have textures for every vertex...
	okayToWriteTexture = 1
	#print "uvsForTexture :"
	#print uvsForTexture
	#print "uvsForFace :"
	#print uvsForFace
	if (len(textureForFace) != len(face)):
		okayToWriteTexture = 0
	if (len(uvsForFace) != len(face)):
		okayToWriteTexture = 0
	for texture in textureForFace:
		if (texture == ''):
			okayToWriteTexture = 0
	# if we're all clear then write out the texture uv coordinates
	if (okayToWriteTexture):
		outputfile.write('TEXTURES\n')
		for i in range(0, len(face)):
			facet = face[i]
			texture = textureForFace[i]
			uvForVertex = uvsForTexture[texture]
			outputfile.write('%s\t1.0 1.0\t%.5f %.5f\t%.5f %.5f\t%.5f %.5f\n' % (texture, uvsForFace[i][0][0], uvsForFace[i][0][1], uvsForFace[i][1][0], uvsForFace[i][1][1], uvsForFace[i][2][0], uvsForFace[i][2][1]))
	outputfile.write('\n')
	outputfile.write('END\n')
	outputfile.close();
print "done"
print ""
#
#	end
#
