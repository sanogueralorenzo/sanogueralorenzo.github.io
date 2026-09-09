using Godot;
using WizNDragons.Core;
namespace WizNDragons;

// A smooth implicit surface joins the billows into one cloud, without sphere seams.
internal static class CloudArt3D
{
    readonly record struct Billow(Vector3 Center, Vector3 Radius);
    static readonly int[][] Tetrahedra = [[0,5,1,6],[0,1,2,6],[0,2,3,6],[0,3,7,6],[0,7,4,6],[0,4,5,6]];
    static readonly Vector3I[] Corners = [new(0,0,0),new(1,0,0),new(1,1,0),new(0,1,0),new(0,0,1),new(1,0,1),new(1,1,1),new(0,1,1)];
    public static ArrayMesh Build(int variant)
    {
        var rng=new SeedRandom((uint)(variant+1)*719);
        var billows=new List<Billow>();
        for(int i=0;i<7;i++)
        {
            float x=(i-3)*.62f, crown=1-Mathf.Abs(i-3)/4f;
            billows.Add(new(new(x,rng.Range(-.1f,.1f)+crown*.25f,Mathf.Sin(i*.9f+variant)*.32f),
                new(rng.Range(.95f,1.2f),rng.Range(.65f,.95f),rng.Range(.85f,1.15f))));
        }
        billows.Add(new(new(-.65f,.72f,-.05f),new(.85f,.88f,.84f)));
        billows.Add(new(new(.55f,.58f,.08f),new(.95f,.82f,.9f)));
        // A tapered hook at each end gives the bank a fairy-tale silhouette.
        for(int side=-1;side<=1;side+=2)for(int i=0;i<4;i++)
        {
            float t=i/3f;
            billows.Add(new(new(side*(2.0f+t*.70f),.08f+t*.40f,.12f+Mathf.Sin(t*2.8f)*.35f),Vector3.One*(.64f-t*.30f)));
        }
        float Field(Vector3 p)
        {
            float sum=0;
            foreach(var b in billows) { var d=(p-b.Center)/b.Radius; float v=1-d.LengthSquared(); if(v>0)sum+=v*v*v; }
            return sum-.19f;
        }
        Vector3 Normal(Vector3 p)
        {
            Vector3 n=default;
            foreach(var b in billows) {var d=(p-b.Center)/b.Radius;float v=1-d.LengthSquared();if(v>0)n+=d/b.Radius*(6*v*v);}
            return n.LengthSquared()>.000001f?n.Normalized():Vector3.Up;
        }
        const int nx=44,ny=24,nz=28;
        Vector3 start=new(-3.4f,-1.15f,-1.8f),step=new(6.8f/nx,3.2f/ny,3.6f/nz);
        int Index(int x,int y,int z)=>(z*(ny+1)+y)*(nx+1)+x;
        var field=new float[(nx+1)*(ny+1)*(nz+1)];
        for(int z=0;z<=nz;z++)for(int y=0;y<=ny;y++)for(int x=0;x<=nx;x++)field[Index(x,y,z)]=Field(start+new Vector3(x,y,z)*step);
        var surface=new SurfaceTool();surface.Begin(Mesh.PrimitiveType.Triangles);
        void Triangle(Vector3 a,Vector3 b,Vector3 c)
        {
            var na=Normal(a);var nb=Normal(b);var nc=Normal(c);
            if((b-a).Cross(c-a).Dot(na+nb+nc)>0){(b,c)=(c,b);(nb,nc)=(nc,nb);}
            surface.SetNormal(na);surface.AddVertex(a);surface.SetNormal(nb);surface.AddVertex(b);surface.SetNormal(nc);surface.AddVertex(c);
        }
        var p=new Vector3[8];var f=new float[8];var inside=new int[4];var outside=new int[4];
        for(int z=0;z<nz;z++)for(int y=0;y<ny;y++)for(int x=0;x<nx;x++)
        {
            for(int i=0;i<8;i++){var c=Corners[i];p[i]=start+new Vector3(x+c.X,y+c.Y,z+c.Z)*step;f[i]=field[Index(x+c.X,y+c.Y,z+c.Z)];}
            foreach(var tetra in Tetrahedra)
            {
                int ni=0,no=0;foreach(int i in tetra){if(f[i]>0)inside[ni++]=i;else outside[no++]=i;}
                if(ni==0||ni==4)continue;
                Vector3 Edge(int a,int b)=>p[a].Lerp(p[b],f[a]/(f[a]-f[b]));
                if(ni==1)Triangle(Edge(inside[0],outside[0]),Edge(inside[0],outside[1]),Edge(inside[0],outside[2]));
                else if(ni==3)Triangle(Edge(outside[0],inside[0]),Edge(outside[0],inside[1]),Edge(outside[0],inside[2]));
                else {var a=Edge(inside[0],outside[0]);var b=Edge(inside[0],outside[1]);var c=Edge(inside[1],outside[0]);var d=Edge(inside[1],outside[1]);Triangle(a,b,c);Triangle(b,d,c);}
            }
        }
        return surface.Commit();
    }
}
